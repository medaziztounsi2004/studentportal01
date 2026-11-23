import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
};

interface RequestBody {
  action:
    | "create_user"
    | "delete_user"
    | "reset_password"
    | "bulk_delete_users"
    | "set_account_status"
    | "approve_password_reset"
    | "toggle_archive";
  email?: string;
  password?: string;
  role?: string;
  full_name?: string;
  phone?: string;
  student_code?: string;
  date_of_birth?: string;
  address?: string;
  niveau_code?: string;
  section_code?: string;
  gender?: string;
  nationality?: string;
  initial_password?: string;
  class_id?: string;
  group_id?: string;
  academic_year_id?: string;
  school_id?: string;
  user_id?: string;
  user_ids?: string[];
  new_password?: string;
  force_password_change?: boolean;
  account_status?: "active" | "paused_unpaid";
  is_active?: boolean;
  request_id?: string;
  admin_notes?: string;
}

function generateSecurePassword(length = 12): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%&*";
  const array = new Uint32Array(length);
  crypto.getRandomValues(array);
  return Array.from(array, (x) => chars[x % chars.length]).join("");
}

function slugify(value: string, fallback = "school"): string {
  const cleaned = value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return cleaned || fallback;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Missing server environment configuration" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Authenticate caller via JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user: callerUser }, error: callerAuthError } = await callerClient.auth.getUser();
    if (callerAuthError || !callerUser) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token", details: callerAuthError }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Admin Client with Service Role Key for privileged operations
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    // 2. Fetch caller role and school_id
    const { data: callerProfile, error: profileError } = await adminClient
      .from("users")
      .select("id, school_id, role, full_name")
      .eq("id", callerUser.id)
      .maybeSingle();

    if (profileError || !callerProfile) {
      return new Response(
        JSON.stringify({ error: "Caller profile not found" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const allowedRoles = ["super_admin", "owner", "admin", "staff"];
    if (!allowedRoles.includes(callerProfile.role)) {
      return new Response(
        JSON.stringify({ error: "Forbidden: You do not have permission to manage users" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const isSuperAdmin = callerProfile.role === "super_admin";
    const body: RequestBody = await req.json();
    const action = body.action;

    // ------------------------------------------------------------------------
    // ACTION: CREATE USER
    // ------------------------------------------------------------------------
    if (action === "create_user") {
      const fullName = body.full_name?.trim();
      const role = body.role || "student";
      const password = body.password || generateSecurePassword();

      if (!fullName) {
        return new Response(
          JSON.stringify({ error: "full_name is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Enforce tenant boundary: school admins can ONLY create users in their own school
      const schoolId = isSuperAdmin ? (body.school_id || callerProfile.school_id) : callerProfile.school_id;

      if (!schoolId) {
        return new Response(
          JSON.stringify({ error: "school_id could not be resolved" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Rule 2: Auto-generate unique school email if student has no email
      let email = body.email?.trim().toLowerCase() || "";
      if (!email && role === "student") {
        const { data: schoolRow } = await adminClient
          .from("schools")
          .select("code, name")
          .eq("id", schoolId)
          .maybeSingle();
        const schoolSlug = slugify(schoolRow?.code || schoolRow?.name || schoolId.slice(0, 8), "school");
        const studentSlug = slugify(
          body.student_code || fullName.split(" ")[0] || "student",
          "student"
        );
        const suffix = body.student_code
          ? slugify(body.student_code, "st")
          : crypto.randomUUID().slice(0, 6);
        let candidate = `${studentSlug}.${suffix}@${schoolSlug}.app`;
        // Ensure zero collision
        const { data: collision } = await adminClient
          .from("users")
          .select("id")
          .ilike("email", candidate)
          .maybeSingle();
        if (collision) {
          candidate = `${studentSlug}.${crypto.randomUUID().slice(0, 6)}@${schoolSlug}.app`;
        }
        email = candidate;
      }

      if (!email) {
        return new Response(
          JSON.stringify({ error: "Email and full_name are required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Rule 1: Global email uniqueness check across ALL schools before creating auth user
      const { data: existingGlobal } = await adminClient
        .from("users")
        .select("id")
        .ilike("email", email)
        .maybeSingle();

      if (existingGlobal) {
        return new Response(
          JSON.stringify({ error: "This email is already registered in the system." }),
          { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Create Supabase Auth User with email_confirm = true (no verification link needed)
      const { data: authData, error: authError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          role,
          full_name: fullName,
          school_id: schoolId,
        },
      });

      if (authError || !authData.user) {
        const msg = (authError?.message || "").toLowerCase();
        const isDuplicate = msg.includes("already") || msg.includes("registered") || msg.includes("exists");
        return new Response(
          JSON.stringify({
            error: isDuplicate
              ? "This email is already registered in the system."
              : (authError?.message || "Failed to create auth user"),
          }),
          { status: isDuplicate ? 409 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const newUserId = authData.user.id;
      const forcePasswordChange =
        body.force_password_change ?? (role === "owner" || role === "admin" || role === "staff");

      // Insert profile in public.users
      const { error: userInsertError } = await adminClient.from("users").insert({
        id: newUserId,
        school_id: schoolId,
        email,
        full_name: fullName,
        role,
        phone: body.phone || null,
        student_code: body.student_code || null,
        date_of_birth: body.date_of_birth || null,
        address: body.address || null,
        niveau_code: body.niveau_code || null,
        section_code: body.section_code || null,
        gender: body.gender || null,
        nationality: body.nationality || null,
        initial_password: password,
        account_status: body.account_status || "active",
        force_password_change: forcePasswordChange,
      });

      if (userInsertError) {
        // Rollback created auth user to maintain state consistency
        await adminClient.auth.admin.deleteUser(newUserId);
        return new Response(
          JSON.stringify({ error: "Failed to create user record", details: userInsertError.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // If student and class assigned, create enrollment
      if (role === "student" && body.class_id) {
        let yearId = body.academic_year_id;
        if (!yearId) {
          const { data: currentYear } = await adminClient
            .from("academic_years")
            .select("id")
            .eq("school_id", schoolId)
            .eq("is_current", true)
            .maybeSingle();
          yearId = currentYear?.id;
        }

        if (yearId) {
          await adminClient.from("enrollments").insert({
            school_id: schoolId,
            user_id: newUserId,
            class_id: body.class_id,
            group_id: body.group_id || null,
            academic_year_id: yearId,
            student_code: body.student_code || null,
            is_active: true,
          });
        }
      }

      // Record audit log
      await adminClient.from("audit_logs").insert({
        school_id: schoolId,
        actor_id: callerUser.id,
        actor_role: callerProfile.role,
        action: "create_user",
        target_table: "users",
        target_id: newUserId,
        new_data: { email, full_name: fullName, role, school_id: schoolId },
      });

      return new Response(
        JSON.stringify({
          success: true,
          user: {
            id: newUserId,
            email,
            full_name: fullName,
            role,
            school_id: schoolId,
            password,
            force_password_change: forcePasswordChange,
          },
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: DELETE USER
    // ------------------------------------------------------------------------
    if (action === "delete_user") {
      const targetUserId = body.user_id;
      if (!targetUserId) {
        return new Response(
          JSON.stringify({ error: "user_id is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Verify target belongs to caller's school
      const { data: targetUser } = await adminClient
        .from("users")
        .select("id, school_id, email, full_name")
        .eq("id", targetUserId)
        .maybeSingle();

      if (!targetUser) {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!isSuperAdmin && targetUser.school_id !== callerProfile.school_id) {
        return new Response(
          JSON.stringify({ error: "Forbidden: Cannot delete user from another school" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Delete from auth & DB
      await adminClient.auth.admin.deleteUser(targetUserId);
      await adminClient.from("users").delete().eq("id", targetUserId);

      // Audit log
      await adminClient.from("audit_logs").insert({
        school_id: targetUser.school_id,
        actor_id: callerUser.id,
        actor_role: callerProfile.role,
        action: "delete_user",
        target_table: "users",
        target_id: targetUserId,
        old_data: { email: targetUser.email, full_name: targetUser.full_name },
      });

      return new Response(
        JSON.stringify({ success: true, user_id: targetUserId }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: RESET PASSWORD
    // ------------------------------------------------------------------------
    if (action === "reset_password") {
      const targetUserId = body.user_id;
      if (!targetUserId) {
        return new Response(
          JSON.stringify({ error: "user_id is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: targetUser } = await adminClient
        .from("users")
        .select("id, school_id")
        .eq("id", targetUserId)
        .maybeSingle();

      if (!targetUser) {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!isSuperAdmin && targetUser.school_id !== callerProfile.school_id) {
        return new Response(
          JSON.stringify({ error: "Forbidden: Cannot reset password for user in another school" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const newPassword = body.new_password || generateSecurePassword();

      await adminClient.auth.admin.updateUserById(targetUserId, {
        password: newPassword,
      });

      await adminClient
        .from("users")
        .update({
          initial_password: newPassword,
          updated_at: new Date().toISOString(),
        })
        .eq("id", targetUserId);

      await adminClient.from("audit_logs").insert({
        school_id: targetUser.school_id,
        actor_id: callerUser.id,
        actor_role: callerProfile.role,
        action: "reset_password",
        target_table: "users",
        target_id: targetUserId,
      });

      return new Response(
        JSON.stringify({ success: true, password: newPassword }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: BULK DELETE USERS
    // ------------------------------------------------------------------------
    if (action === "bulk_delete_users") {
      const userIds = body.user_ids || [];
      let deleted = 0;
      let failed = 0;

      for (const id of userIds) {
        try {
          const { data: target } = await adminClient
            .from("users")
            .select("id, school_id")
            .eq("id", id)
            .maybeSingle();

          if (!target || (!isSuperAdmin && target.school_id !== callerProfile.school_id)) {
            failed++;
            continue;
          }

          await adminClient.auth.admin.deleteUser(id);
          await adminClient.from("users").delete().eq("id", id);
          deleted++;
        } catch (_) {
          failed++;
        }
      }

      return new Response(
        JSON.stringify({ success: true, deleted, failed }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: SET ACCOUNT STATUS (active | paused_unpaid)
    // ------------------------------------------------------------------------
    if (action === "set_account_status") {
      const targetUserId = body.user_id;
      const accountStatus = body.account_status;
      if (!targetUserId || (accountStatus !== "active" && accountStatus !== "paused_unpaid")) {
        return new Response(
          JSON.stringify({ error: "user_id and valid account_status ('active' | 'paused_unpaid') are required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: targetUser } = await adminClient
        .from("users")
        .select("id, school_id, account_status")
        .eq("id", targetUserId)
        .maybeSingle();

      if (!targetUser) {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!isSuperAdmin && targetUser.school_id !== callerProfile.school_id) {
        return new Response(
          JSON.stringify({ error: "Forbidden: Cannot update account status for user in another school" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      await adminClient
        .from("users")
        .update({ account_status: accountStatus, updated_at: new Date().toISOString() })
        .eq("id", targetUserId);

      await adminClient.from("audit_logs").insert({
        school_id: targetUser.school_id,
        actor_id: callerUser.id,
        actor_role: callerProfile.role,
        action: "set_account_status",
        target_table: "users",
        target_id: targetUserId,
        old_data: { account_status: targetUser.account_status },
        new_data: { account_status: accountStatus },
      });

      return new Response(
        JSON.stringify({ success: true, account_status: accountStatus }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: TOGGLE ARCHIVE (is_active)
    // ------------------------------------------------------------------------
    if (action === "toggle_archive") {
      const targetUserIds = body.user_ids || (body.user_id ? [body.user_id] : []);
      const isActive = body.is_active ?? false;
      if (targetUserIds.length === 0) {
        return new Response(
          JSON.stringify({ error: "user_id or user_ids is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: result, error: rpcError } = await adminClient.rpc("toggle_user_active_status", {
        p_user_ids: targetUserIds,
        p_is_active: isActive,
      });

      if (rpcError) {
        return new Response(
          JSON.stringify({ error: rpcError.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ success: true, is_active: isActive, result }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ------------------------------------------------------------------------
    // ACTION: APPROVE PASSWORD RESET REQUEST (No raw password stored in table)
    // ------------------------------------------------------------------------
    if (action === "approve_password_reset") {
      const requestId = body.request_id;
      const targetUserId = body.user_id;
      if (!requestId && !targetUserId) {
        return new Response(
          JSON.stringify({ error: "request_id or user_id is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      let resolvedUserId = targetUserId;
      if (requestId && !resolvedUserId) {
        const { data: reqRow } = await adminClient
          .from("password_reset_requests")
          .select("user_id")
          .eq("id", requestId)
          .maybeSingle();
        resolvedUserId = reqRow?.user_id;
      }

      if (!resolvedUserId) {
        return new Response(
          JSON.stringify({ error: "No linked user account for this request" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const { data: targetUser } = await adminClient
        .from("users")
        .select("id, school_id")
        .eq("id", resolvedUserId)
        .maybeSingle();

      if (!targetUser) {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!isSuperAdmin && targetUser.school_id !== callerProfile.school_id) {
        return new Response(
          JSON.stringify({ error: "Forbidden: Cannot approve request for user in another school" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const newPassword = body.new_password?.trim() || generateSecurePassword();

      const { error: authUpdErr } = await adminClient.auth.admin.updateUserById(resolvedUserId, {
        password: newPassword,
      });

      if (authUpdErr) {
        return new Response(
          JSON.stringify({ error: authUpdErr.message }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      await adminClient
        .from("users")
        .update({
          initial_password: newPassword,
          updated_at: new Date().toISOString(),
        })
        .eq("id", resolvedUserId);

      if (requestId) {
        await adminClient
          .from("password_reset_requests")
          .update({
            status: "approved",
            processed_at: new Date().toISOString(),
            processed_by: callerUser.id,
            new_password_sent: true,
            admin_notes: body.admin_notes || "Approuvé par l'administration",
          })
          .eq("id", requestId);
      }

      await adminClient.from("audit_logs").insert({
        school_id: targetUser.school_id,
        actor_id: callerUser.id,
        actor_role: callerProfile.role,
        action: "approve_password_reset",
        target_table: "users",
        target_id: resolvedUserId,
      });

      return new Response(
        JSON.stringify({ success: true, password: newPassword }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: `Unknown action: ${action}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
