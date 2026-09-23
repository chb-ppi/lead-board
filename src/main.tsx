import { FormEvent, useEffect, useState } from "react";
import { createClient, Session } from "@supabase/supabase-js";
import { createRoot } from "react-dom/client";
import "./styles.css";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey)
  throw new Error("Supabase environment variables are missing.");

const supabase = createClient(supabaseUrl, supabaseAnonKey);
type Row = Record<string, string>;
type Profile = Row & {
  role: "team_lead" | "employee";
  team_id: string;
  must_change_password?: boolean;
};

const fields: Record<string, Array<[string, string, string?]>> = {
  customers: [["name", "Kunde"]],
  projects: [
    ["name", "Projekt"],
    ["customer_id", "Kunde", "customers"],
  ],
  employee_assignments: [
    ["project_id", "Projekt", "projects"],
    ["employee_id", "Mitarbeiter", "profiles"],
    ["starts_on", "Einsatzbeginn", "date"],
    ["ends_on", "Einsatzende", "date"],
    ["available_days", "Verfuegbare Arbeitstage", "number"],
  ],
  offers: [
    ["customer_id", "Kunde", "customers"],
    ["project_id", "Projekt", "projects"],
    ["employee_id", "Mitarbeiter", "profiles"],
    ["starts_on", "Angebotsbeginn", "date"],
    ["ends_on", "Angebotsende", "date"],
    ["offered_days", "Angebotene Tage", "number"],
    ["daily_rate", "Tagessatz (EUR)", "number"],
    ["status", "Verhandlungsstatus", "offer_status"],
  ],
};

const offerStatuses = [
  ["draft", "Entwurf"],
  ["sent", "Versendet"],
  ["negotiation", "In Verhandlung"],
  ["accepted", "Gewonnen"],
  ["rejected", "Verloren"],
];

function label(row: Row, table: string) {
  if (table === "profiles") return `${row.email} (${row.role})`;
  if (table === "employee_assignments")
    return `${row.employee_id?.slice(0, 8)} · ${row.project_id?.slice(0, 8)}`;
  if (table === "offers")
    return `${row.employee_id?.slice(0, 8)} · ${row.offered_days} Tage`;
  return row.name || row.id.slice(0, 8);
}

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [createAccount, setCreateAccount] = useState(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [rows, setRows] = useState<Record<string, Row[]>>({});
  const [teamName, setTeamName] = useState("");
  const [signupTeams, setSignupTeams] = useState<Row[]>([]);
  const [signupTeamId, setSignupTeamId] = useState("");

  async function load() {
    const tables = ["teams", "profiles", ...Object.keys(fields)];
    const results = await Promise.all(
      tables.map((table) =>
        supabase.from(table).select("*").order("created_at"),
      ),
    );
    const loaded = Object.fromEntries(
      tables.map((table, index) => [
        table,
        (results[index].data ?? []) as Row[],
      ]),
    );
    setRows(loaded);
    const ownProfile = loaded.profiles.find(
      (item) => item.id === session?.user.id,
    ) as Profile | undefined;
    setProfile(ownProfile ?? null);
  }

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, nextSession) => setSession(nextSession),
    );
    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (createAccount)
      void supabase
        .from("teams")
        .select("id, name")
        .order("name")
        .then(({ data }) => setSignupTeams((data ?? []) as Row[]));
  }, [createAccount]);

  useEffect(() => {
    if (session) void load();
  }, [session]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    const result = createAccount
      ? await supabase.auth.signUp({
          email,
          password,
          options: { data: signupTeamId ? { team_id: signupTeamId } : {} },
        })
      : await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    setMessage(
      result.error
        ? result.error.message
        : createAccount
          ? "Konto erstellt. Du bist jetzt angemeldet."
          : "",
    );
  }

  async function createTeam(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    const result = await supabase.rpc("create_team", {
      team_name: teamName,
    });
    setBusy(false);
    if (result.error) setMessage(result.error.message);
    else {
      setTeamName("");
      await load();
    }
  }

  if (!session)
    return (
      <main className="card auth">
        <p className="eyebrow">Lead Board</p>
        <h1>{createAccount ? "Lokales Konto anlegen" : "Anmelden"}</h1>
        <form onSubmit={submit}>
          <label>
            E-Mail
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
            />
          </label>
          {createAccount && signupTeams.length > 0 && (
            <label>
              Bestehendem Team beitreten (optional)
              <select
                value={signupTeamId}
                onChange={(event) => setSignupTeamId(event.target.value)}
              >
                <option value="">Ohne Team fortfahren</option>
                {signupTeams.map((team) => (
                  <option key={team.id} value={team.id}>
                    {team.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <label>
            Passwort
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              minLength={6}
              required
            />
          </label>
          {message && <p className="message">{message}</p>}
          <button disabled={busy}>
            {busy
              ? "Bitte warten..."
              : createAccount
                ? "Konto erstellen"
                : "Anmelden"}
          </button>
        </form>
        <button
          className="link"
          onClick={() => {
            setCreateAccount(!createAccount);
            setMessage("");
          }}
        >
          {createAccount
            ? "Bereits ein Konto? Anmelden"
            : "Noch kein Konto? Konto erstellen"}
        </button>
      </main>
    );

  if (!profile)
    return (
      <main className="card">
        <p className="eyebrow">Lead Board</p>
        <h1>Profil wird eingerichtet</h1>
        <p className="muted">
          Das Konto wurde angelegt. Bitte lade die Seite erneut, falls das
          Profil noch nicht sichtbar ist.
        </p>
      </main>
    );

  if (profile.must_change_password) return <PasswordChange profile={profile} />;

  if (!profile.team_id && profile.role === "team_lead")
    return (
      <main className="card">
        <p className="eyebrow">Ersteinrichtung</p>
        <h1>Erstes Team anlegen</h1>
        <p>
          Du bist Teamleitung. Lege dein erstes Team an, um mit der Datenpflege
          zu beginnen.
        </p>
        <form onSubmit={createTeam}>
          <label>
            Teamname
            <input
              value={teamName}
              onChange={(event) => setTeamName(event.target.value)}
              required
            />
          </label>
          {message && <p className="message">{message}</p>}
          <button disabled={busy}>Team einrichten</button>
        </form>
        <button className="link" onClick={() => supabase.auth.signOut()}>
          Abmelden
        </button>
      </main>
    );

  if (!profile.team_id)
    return (
      <main className="card">
        <p className="eyebrow">Lead Board</p>
        <h1>Noch keinem Team zugeordnet</h1>
        <p className="muted">
          Du kannst derzeit keine Teamdaten sehen oder bearbeiten. Wähle ein
          Team bei der Registrierung oder lass dich von einer Teamleitung
          zuordnen.
        </p>
        <button className="link" onClick={() => supabase.auth.signOut()}>
          Abmelden
        </button>
      </main>
    );

  return (
    <main className="app">
      <header>
        <div>
          <p className="eyebrow">Lead Board</p>
          <h1>{profile.role === "team_lead" ? "Teamleitung" : "Mein Team"}</h1>
          <p>{profile.email}</p>
        </div>
        <button onClick={() => supabase.auth.signOut()}>Abmelden</button>
      </header>
      <section className="notice">
        {profile.role === "team_lead"
          ? "Du siehst und verwaltest ausschließlich Daten deines Teams."
          : "Du siehst und verwaltest ausschließlich Daten deines Teams."}
      </section>
      <Overview rows={rows} isTeamLead={profile.role === "team_lead"} />
      {profile.role === "team_lead" && (
        <EmployeeInvitation onSaved={load} session={session} />
      )}
      <section>
        <h2>Datenpflege</h2>
        <div className="grid">
          {Object.keys(fields).map((table) => (
            <Editor
              key={table}
              table={table}
              rows={rows}
              teamId={profile.team_id}
              isTeamLead={profile.role === "team_lead"}
              onSaved={load}
            />
          ))}
        </div>
      </section>
    </main>
  );
}

function PasswordChange({ profile }: { profile: Profile }) {
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    const update = await supabase.auth.updateUser({ password });
    const completion = update.error
      ? null
      : await supabase.rpc("complete_initial_password_change");
    setBusy(false);
    if (update.error || completion?.error)
      setMessage(
        update.error?.message ?? completion?.error?.message ?? "Fehler",
      );
    else window.location.reload();
  }
  return (
    <main className="card auth">
      <p className="eyebrow">Willkommen, {profile.name}</p>
      <h1>Passwort festlegen</h1>
      <p className="muted">
        Bitte lege vor der ersten Nutzung ein eigenes Passwort fest.
      </p>
      <form onSubmit={save}>
        <label>
          Neues Passwort
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            minLength={6}
            required
          />
        </label>
        {message && <p className="message">{message}</p>}
        <button disabled={busy}>
          {busy ? "Bitte warten..." : "Passwort speichern"}
        </button>
      </form>
    </main>
  );
}

function EmployeeInvitation({
  session,
  onSaved,
}: {
  session: Session;
  onSaved: () => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  async function invite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    const response = await fetch("/api/employees", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ name, email }),
    });
    const result = await response.json();
    setBusy(false);
    if (!response.ok)
      setMessage(
        result.error ?? "Die Einladung konnte nicht versendet werden.",
      );
    else {
      setName("");
      setEmail("");
      setMessage(result.message);
      await onSaved();
    }
  }
  return (
    <section>
      <h2>Mitarbeiter einladen</h2>
      <form className="membership" onSubmit={invite}>
        <label>
          Name
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            required
          />
        </label>
        <label>
          E-Mail
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
          />
        </label>
        <button disabled={busy}>{busy ? "Bitte warten..." : "Einladen"}</button>
      </form>
      {message && (
        <p
          className={message.startsWith("Mitarbeiter") ? "success" : "message"}
        >
          {message}
        </p>
      )}
    </section>
  );
}

function Overview({
  rows,
  isTeamLead,
}: {
  rows: Record<string, Row[]>;
  isTeamLead: boolean;
}) {
  const byId = (table: string, id: string | undefined) =>
    rows[table]?.find((row) => row.id === id);
  const name = (table: string, id: string | undefined) =>
    byId(table, id)?.name ?? "-";
  const employee = (id: string | undefined) =>
    byId("profiles", id)?.email ?? "-";
  const team = (id: string | undefined) => name("teams", id);
  const status = (value: string | undefined) =>
    offerStatuses.find(([key]) => key === value)?.[1] ?? value ?? "-";
  const money = (value: string | undefined) =>
    value ? `${Number(value).toLocaleString("de-DE")} EUR` : "-";

  return (
    <section className="overview">
      <div>
        <p className="eyebrow">Übersicht</p>
        <h2>{isTeamLead ? "Alle Teams" : "Mein Team"}</h2>
        <p className="muted">
          {isTeamLead
            ? "Einsätze und Angebote aller Teams."
            : "Einsätze und Angebote deines Teams."}
        </p>
      </div>
      <h3>Projekte und Einsätze</h3>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Mitarbeiter</th>
              <th>Team</th>
              <th>Projekt</th>
              <th>Kunde</th>
              <th>Einsatzzeitraum</th>
              <th>Verfügbare Arbeitstage</th>
            </tr>
          </thead>
          <tbody>
            {(rows.employee_assignments ?? []).map((assignment) => {
              const project = byId("projects", assignment.project_id);
              return (
                <tr key={assignment.id}>
                  <td>{employee(assignment.employee_id)}</td>
                  <td>{team(assignment.team_id)}</td>
                  <td>{project?.name ?? "-"}</td>
                  <td>{name("customers", project?.customer_id)}</td>
                  <td>
                    {assignment.starts_on} bis {assignment.ends_on ?? "offen"}
                  </td>
                  <td>{assignment.available_days}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {!rows.employee_assignments?.length && (
          <p className="empty">Noch keine Einsätze vorhanden.</p>
        )}
      </div>
      <h3>Angebote</h3>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Kunde</th>
              <th>Projekt</th>
              <th>Mitarbeiter</th>
              <th>Team</th>
              <th>Angebotene Tage</th>
              <th>Tagessatz</th>
              <th>Verhandlungsstatus</th>
            </tr>
          </thead>
          <tbody>
            {(rows.offers ?? []).map((offer) => (
              <tr key={offer.id}>
                <td>{name("customers", offer.customer_id)}</td>
                <td>{name("projects", offer.project_id)}</td>
                <td>{employee(offer.employee_id)}</td>
                <td>{team(offer.team_id)}</td>
                <td>{offer.offered_days}</td>
                <td>{money(offer.daily_rate)}</td>
                <td>{status(offer.status)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.offers?.length && (
          <p className="empty">Noch keine Angebote vorhanden.</p>
        )}
      </div>
    </section>
  );
}

function TeamManager({
  rows,
  onSaved,
}: {
  rows: Record<string, Row[]>;
  onSaved: () => Promise<void>;
}) {
  const [name, setName] = useState("");
  async function add(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (
      await supabase
        .from("teams")
        .insert({ name })
        .then(({ error }) => !error)
    ) {
      setName("");
      await onSaved();
    }
  }
  return (
    <section>
      <h2>Teams</h2>
      <form className="compact" onSubmit={add}>
        <input
          aria-label="Teamname"
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="Neues Team"
          required
        />
        <button>Hinzufügen</button>
      </form>
      <p className="muted">
        {rows.teams?.map((team) => team.name).join(" · ")}
      </p>
    </section>
  );
}

function MembershipManager({
  rows,
  onSaved,
}: {
  rows: Record<string, Row[]>;
  onSaved: () => Promise<void>;
}) {
  const [profileId, setProfileId] = useState("");
  const selected = rows.profiles?.find((item) => item.id === profileId);
  const [teamId, setTeamId] = useState("");
  const [role, setRole] = useState("employee");
  function select(id: string) {
    const next = rows.profiles?.find((item) => item.id === id);
    setProfileId(id);
    setTeamId(next?.team_id ?? "");
    setRole(next?.role ?? "employee");
  }
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (
      profileId &&
      !(
        await supabase
          .from("profiles")
          .update({ team_id: teamId, role })
          .eq("id", profileId)
      ).error
    )
      await onSaved();
  }
  return (
    <section>
      <h2>Teammitgliedschaften</h2>
      <form className="membership" onSubmit={save}>
        <label>
          Mitarbeiter
          <select
            value={profileId}
            onChange={(event) => select(event.target.value)}
          >
            <option value="">Auswählen</option>
            {rows.profiles?.map((item) => (
              <option key={item.id} value={item.id}>
                {label(item, "profiles")}
              </option>
            ))}
          </select>
        </label>
        <label>
          Team
          <select
            value={teamId}
            onChange={(event) => setTeamId(event.target.value)}
            required
          >
            <option value="">Auswählen</option>
            {rows.teams?.map((team) => (
              <option key={team.id} value={team.id}>
                {team.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Rolle
          <select
            value={role}
            onChange={(event) => setRole(event.target.value)}
          >
            <option value="employee">Mitarbeiter</option>
            <option value="team_lead">Teamleitung</option>
          </select>
        </label>
        <button disabled={!selected}>Speichern</button>
      </form>
    </section>
  );
}

function Editor({
  table,
  rows,
  teamId,
  isTeamLead,
  onSaved,
}: {
  table: string;
  rows: Record<string, Row[]>;
  teamId: string;
  isTeamLead: boolean;
  onSaved: () => Promise<void>;
}) {
  const [selected, setSelected] = useState("new");
  const [values, setValues] = useState<Row>({});
  const [selectedTeamId, setSelectedTeamId] = useState(teamId);
  const [error, setError] = useState("");
  const [warning, setWarning] = useState("");
  const definition = fields[table];
  const existing = rows[table] ?? [];
  const effectiveTeamId = selected === "new" ? selectedTeamId : values.team_id;
  const changeSelected = (id: string) => {
    const next =
      id === "new" ? {} : (existing.find((item) => item.id === id) ?? {});
    setSelected(id);
    setValues(next);
    setSelectedTeamId(next.team_id ?? teamId);
    setError("");
    setWarning("");
  };
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setWarning("");
    if (
      table === "employee_assignments" &&
      values.ends_on &&
      values.starts_on &&
      values.ends_on < values.starts_on
    ) {
      setError("Das Einsatzende darf nicht vor dem Einsatzbeginn liegen.");
      return;
    }
    if (
      table === "offers" &&
      values.ends_on &&
      values.starts_on &&
      values.ends_on < values.starts_on
    ) {
      setError("Das Angebotsende darf nicht vor dem Angebotsbeginn liegen.");
      return;
    }
    const matchingAssignment =
      table === "offers"
        ? (rows.employee_assignments ?? []).find(
            (assignment) =>
              assignment.team_id === effectiveTeamId &&
              assignment.employee_id === values.employee_id &&
              assignment.project_id === values.project_id &&
              assignment.starts_on <= values.starts_on &&
              (!assignment.ends_on || assignment.ends_on >= values.ends_on),
          )
        : undefined;
    const offeredDays = Number(values.offered_days);
    const availableDays = Number(matchingAssignment?.available_days);
    let capacityWarning = "";
    if (
      table === "offers" &&
      matchingAssignment &&
      offeredDays > availableDays
    ) {
      capacityWarning = `Kapazitaetswarnung: ${offeredDays} angebotene Tage uebersteigen ${availableDays} verfuegbare Tage. Das Angebot wird trotzdem gespeichert.`;
      setWarning(capacityWarning);
    }
    const payload = Object.fromEntries(
      definition.map(([key]) => [key, values[key] || null]),
    );
    const query =
      selected === "new"
        ? supabase.from(table).insert({ ...payload, team_id: selectedTeamId })
        : supabase.from(table).update(payload).eq("id", selected);
    const result = await query;
    if (result.error) setError(result.error.message);
    else {
      changeSelected("new");
      await onSaved();
      setWarning(capacityWarning);
    }
  }
  return (
    <article>
      <h3>
        {
          (
            {
              customers: "Kunden",
              projects: "Projekte",
              employee_assignments: "Einsätze",
              offers: "Angebote",
            } as Record<string, string>
          )[table]
        }
      </h3>
      <label>
        Datensatz
        <select
          value={selected}
          onChange={(event) => changeSelected(event.target.value)}
        >
          <option value="new">Neu anlegen</option>
          {existing.map((row) => (
            <option key={row.id} value={row.id}>
              {label(row, table)}
            </option>
          ))}
        </select>
      </label>
      <form onSubmit={save}>
        {selected === "new" && isTeamLead && (
          <label>
            Team
            <select
              value={selectedTeamId}
              onChange={(event) => setSelectedTeamId(event.target.value)}
            >
              {rows.teams?.map((team) => (
                <option key={team.id} value={team.id}>
                  {team.name}
                </option>
              ))}
            </select>
          </label>
        )}
        {definition.map(([key, fieldLabel, source]) => (
          <label key={key}>
            {fieldLabel}
            {source === "offer_status" ? (
              <select
                value={values[key] ?? "draft"}
                onChange={(event) =>
                  setValues({ ...values, [key]: event.target.value })
                }
              >
                {offerStatuses.map(([value, statusLabel]) => (
                  <option key={value} value={value}>
                    {statusLabel}
                  </option>
                ))}
              </select>
            ) : source && !["date", "number"].includes(source) ? (
              <select
                value={values[key] ?? ""}
                onChange={(event) =>
                  setValues({ ...values, [key]: event.target.value })
                }
                required
              >
                <option value="">Auswählen</option>
                {(rows[source] ?? [])
                  .filter(
                    (row) =>
                      row.team_id === effectiveTeamId &&
                      (source !== "projects" ||
                        !values.customer_id ||
                        row.customer_id === values.customer_id),
                  )
                  .map((row) => (
                    <option key={row.id} value={row.id}>
                      {label(row, source)}
                    </option>
                  ))}
              </select>
            ) : (
              <input
                type={source || "text"}
                min={key === "ends_on" ? values.starts_on : undefined}
                step={source === "number" ? "0.01" : undefined}
                value={values[key] ?? ""}
                onChange={(event) =>
                  setValues({ ...values, [key]: event.target.value })
                }
                required={key !== "ends_on"}
              />
            )}
          </label>
        ))}
        {error && <p className="message">{error}</p>}
        {warning && <p className="warning">{warning}</p>}
        <button>{selected === "new" ? "Anlegen" : "Speichern"}</button>
      </form>
    </article>
  );
}

createRoot(document.getElementById("root")!).render(<App />);
