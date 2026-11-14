# Play data

The browser playtest can send anonymous play data to the game's maker, to balance the game. This page says what is sent and how to stop it.

**Off until you say yes.** The title screen asks once. You can change your answer any time in Settings, under "Share anonymous play data".

**If you say yes**, the game sends:
- a random player id, made on your device when you say yes, so your runs can be told apart from other players'. It is not tied to a name, email or account;
- when the game opens: that id, the build, your screen size and language;
- each run as you play it: the run's record (the choices you made, each round and night, your heroes, relics and the result), the build, how long the run has been open, and the settings that change how a run plays.

**Whether or not you say yes**, opening the page counts one visit, with no id and nothing stored on your device: the build, screen size, language and the domain of the site that linked you.

**Never sent:** names, emails, your IP address (the database host's own short-lived logs see it, as any website's do), anything from developer builds.

**Deleting your data:** Settings shows your player id when sharing is on. Send it to the game's maker and every run and session under it is deleted. Clearing your browser's site data makes the game forget the id.

Where it goes: a Supabase database (tables in `tools/telemetry/schema.sql`). The key inside the game can only add data, never read it.
