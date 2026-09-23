import http from "node:http";

const authUrl = process.env.AUTH_URL ?? "http://auth:9999";
const restUrl = process.env.REST_URL ?? "http://rest:3000";
const serviceRoleKey = process.env.SERVICE_ROLE_KEY;
const siteUrl = process.env.SITE_URL ?? "http://localhost:3000";

if (!serviceRoleKey) throw new Error("SERVICE_ROLE_KEY is required.");

function send(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

async function request(url, options = {}) {
  const response = await fetch(url, options);
  const body = await response.json().catch(() => ({}));
  return { response, body };
}

const serviceHeaders = {
  Authorization: `Bearer ${serviceRoleKey}`,
  apikey: serviceRoleKey,
};

http
  .createServer(async (requestMessage, response) => {
    const match = requestMessage.url?.match(
      /^\/api\/employees\/([^/]+)\/account$/,
    );
    if (requestMessage.method !== "POST" || !match) {
      send(response, 404, { error: "Nicht gefunden." });
      return;
    }

    const authorization = requestMessage.headers.authorization;
    if (!authorization?.startsWith("Bearer ")) {
      send(response, 401, { error: "Anmeldung erforderlich." });
      return;
    }

    let payload = "";
    for await (const chunk of requestMessage) payload += chunk;
    const { action } = JSON.parse(payload || "{}");
    if (!["deactivate", "activate", "reset"].includes(action)) {
      send(response, 400, { error: "Ungültige Kontenaktion." });
      return;
    }

    const user = await request(`${authUrl}/user`, {
      headers: { Authorization: authorization, apikey: serviceRoleKey },
    });
    if (!user.response.ok) {
      send(response, 401, { error: "Anmeldung ungültig oder abgelaufen." });
      return;
    }

    const profile = await request(
      `${restUrl}/profiles?id=eq.${encodeURIComponent(user.body.id)}&select=role,team_id`,
      { headers: serviceHeaders },
    );
    const currentProfile = profile.body[0];
    const employee = await request(
      `${restUrl}/profiles?id=eq.${encodeURIComponent(match[1])}&select=id,email,role,team_id`,
      { headers: serviceHeaders },
    );
    const targetProfile = employee.body[0];
    if (
      !profile.response.ok ||
      !employee.response.ok ||
      currentProfile?.role !== "team_lead" ||
      !currentProfile.team_id ||
      targetProfile?.role !== "employee" ||
      targetProfile?.team_id !== currentProfile.team_id
    ) {
      send(response, 403, {
        error: "Dieses Konto darf nicht verwaltet werden.",
      });
      return;
    }

    if (action === "reset") {
      const reset = await request(`${authUrl}/recover`, {
        method: "POST",
        headers: { ...serviceHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({
          email: targetProfile.email,
          redirect_to: siteUrl,
        }),
      });
      const update = await request(
        `${restUrl}/profiles?id=eq.${encodeURIComponent(targetProfile.id)}`,
        {
          method: "PATCH",
          headers: {
            ...serviceHeaders,
            "Content-Type": "application/json",
            Prefer: "return=minimal",
          },
          body: JSON.stringify({
            last_reset_requested_at: new Date().toISOString(),
            reset_status: reset.response.ok ? "sent" : "failed",
          }),
        },
      );
      if (!reset.response.ok || !update.response.ok) {
        send(response, 502, {
          error:
            "Der Passwortzurücksetzungsprozess konnte nicht ausgelöst werden.",
        });
        return;
      }
      send(response, 200, {
        message: "Passwortzurücksetzung wurde ausgelöst.",
      });
      return;
    }

    const authUpdate = await request(
      `${authUrl}/admin/users/${targetProfile.id}`,
      {
        method: "PUT",
        headers: { ...serviceHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({
          ban_duration: action === "deactivate" ? "876000h" : "none",
        }),
      },
    );
    if (!authUpdate.response.ok) {
      send(response, 502, {
        error: "Der Kontostatus konnte nicht geändert werden.",
      });
      return;
    }
    const profileUpdate = await request(
      `${restUrl}/profiles?id=eq.${encodeURIComponent(targetProfile.id)}`,
      {
        method: "PATCH",
        headers: {
          ...serviceHeaders,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ is_active: action === "activate" }),
      },
    );
    if (!profileUpdate.response.ok) {
      send(response, 502, {
        error: "Der Kontostatus konnte nicht geändert werden.",
      });
      return;
    }
    send(response, 200, {
      message:
        action === "activate" ? "Konto aktiviert." : "Konto deaktiviert.",
    });
  })
  .listen(3001);
