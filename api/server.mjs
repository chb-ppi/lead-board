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

http
  .createServer(async (requestMessage, response) => {
    if (
      requestMessage.method !== "POST" ||
      requestMessage.url !== "/api/employees"
    ) {
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
    const { name, email } = JSON.parse(payload || "{}");
    const normalizedName = typeof name === "string" ? name.trim() : "";
    const normalizedEmail =
      typeof email === "string" ? email.trim().toLowerCase() : "";
    if (!normalizedName || !/^\S+@\S+\.\S+$/.test(normalizedEmail)) {
      send(response, 400, {
        error: "Name und eine gültige E-Mail-Adresse sind erforderlich.",
      });
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
      {
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
        },
      },
    );
    const currentProfile = profile.body[0];
    if (
      !profile.response.ok ||
      currentProfile?.role !== "team_lead" ||
      !currentProfile.team_id
    ) {
      send(response, 403, {
        error: "Nur Teamleitungen können Mitarbeiter anlegen.",
      });
      return;
    }

    const duplicate = await request(
      `${restUrl}/profiles?email=ilike.${encodeURIComponent(normalizedEmail)}&select=id`,
      {
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
        },
      },
    );
    if (Array.isArray(duplicate.body) && duplicate.body.length) {
      send(response, 409, {
        error: "Diese E-Mail-Adresse wird bereits verwendet.",
      });
      return;
    }

    const invitation = await request(`${authUrl}/invite`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email: normalizedEmail, redirect_to: siteUrl }),
    });
    if (!invitation.response.ok) {
      const error = invitation.body.msg?.toLowerCase().includes("already")
        ? "Diese E-Mail-Adresse wird bereits verwendet."
        : "Die Einladung konnte nicht versendet werden.";
      send(response, 400, { error });
      return;
    }

    const update = await request(
      `${restUrl}/profiles?id=eq.${encodeURIComponent(invitation.body.id)}`,
      {
        method: "PATCH",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({
          name: normalizedName,
          role: "employee",
          team_id: currentProfile.team_id,
          must_change_password: true,
        }),
      },
    );
    if (!update.response.ok) {
      send(response, 500, {
        error: "Das Konto konnte nicht dem Team zugeordnet werden.",
      });
      return;
    }

    send(response, 201, {
      message: "Mitarbeiter angelegt und Einladung versendet.",
    });
  })
  .listen(3001);
