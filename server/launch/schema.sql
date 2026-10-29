-- wya?! database, for Supabase (Postgres). Run once in the project's SQL editor.
-- Written 24 Sep 2026 night. Checked against a plain Postgres 16 with Supabase's auth stubbed;
-- not yet run on a real Supabase project.
--
-- The rules every table follows:
--   * Row Level Security is on everywhere; what a person can read or change is written below.
--   * Nothing here stores an ID document or a selfie: the ID-check company keeps those, and
--     this database keeps only "verified, over 18, on this date".
--   * Solo locations are stored rounded to 0.05 degrees (about 5 km) and expire after a day,
--     and nobody can read them directly: solo_near() answers "who is near me" instead.

create extension if not exists citext;

-- ---------- people ----------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  handle        citext unique not null check (handle ~ '^[a-z0-9._]{2,24}$'),
  name          text not null check (char_length(name) between 1 and 30),
  bio           text not null default '' check (char_length(bio) <= 120),
  home          text not null default '' check (char_length(home) <= 80),
  picture       jsonb not null default '{}'::jsonb,        -- a colour, a field or a photo's storage key
  nationalities text[] not null default '{}',              -- ISO codes; travel advice follows these
  private       boolean not null default false,
  premium       boolean not null default false,            -- set by the purchase webhook only
  handle_changes timestamptz[] not null default '{}',      -- twice in any 14 days (D136)
  created_at    timestamptz not null default now()
);

-- two handle changes in any 14 days; the name changes freely
create function public.handle_guard() returns trigger language plpgsql as $$
declare recent timestamptz[];
begin
  if new.handle is distinct from old.handle then
    recent := array(select t from unnest(old.handle_changes) t where t > now() - interval '14 days');
    if coalesce(array_length(recent, 1), 0) >= 2 then
      raise exception 'Your handle can change twice in 14 days';
    end if;
    new.handle_changes := recent || now();
  end if;
  if new.premium is distinct from old.premium
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                  current_setting('request.jwt.claim.role', true)) is distinct from 'service_role' then
    new.premium := old.premium;   -- only the server sets premium
  end if;
  return new;
end $$;
create trigger profiles_handle before update on public.profiles for each row execute function public.handle_guard();

create table public.follows (
  follower  uuid references public.profiles (id) on delete cascade,
  followee  uuid references public.profiles (id) on delete cascade,
  status    text not null default 'accepted' check (status in ('requested', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);

create table public.blocks (
  blocker uuid references public.profiles (id) on delete cascade,
  blocked uuid references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked)
);

-- ---------- the map ----------
create table public.stamps (
  user_id    uuid references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('country', 'region', 'place')),
  key        text not null,                                 -- 'fr', 'FRA1_7', a place id
  details    jsonb not null default '{}'::jsonb,            -- when, why, how, the kind of place
  stamped_at timestamptz not null default now(),
  primary key (user_id, kind, key)
);
create table public.wishes (
  user_id    uuid references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('country', 'region', 'place')),
  key        text not null,
  level      smallint not null default 3 check (level between 1 and 5),
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, key)
);
create table public.pins (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  lat        double precision not null, lon double precision not null,
  note       text not null default '' check (char_length(note) <= 280),
  pinned_on  date,
  created_at timestamptz not null default now()
);

-- ---------- lists, plans, tier lists, books ----------
create table public.things (
  id          uuid primary key default gen_random_uuid(),
  owner       uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('list', 'plan', 'tier', 'book')),
  name        text not null check (char_length(name) between 1 and 60),
  body        jsonb not null default '{}'::jsonb,           -- rows, days, tiers or pages, as the app keeps them
  visibility  text not null default 'me' check (visibility in ('me', 'friends', 'everyone')),
  published_at timestamptz,                                  -- in Discover when set
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);
create table public.thing_editors (
  thing_id uuid references public.things (id) on delete cascade,
  user_id  uuid references public.profiles (id) on delete cascade,
  primary key (thing_id, user_id)
);

-- ---------- posts and what people do to things ----------
create table public.posts (
  id         uuid primary key default gen_random_uuid(),
  author     uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('photo', 'video', 'text', 'link')),
  body       jsonb not null default '{}'::jsonb,            -- words (300 at most), media keys, a link's source
  place      text,                                          -- 'place:fo|Tórshavn' or 'country:fo'
  created_at timestamptz not null default now()
);
-- anything that can be liked, saved or commented on is named by a target string:
-- 'post:<uuid>', 'thing:<uuid>', 'country:fr', 'place:fo|Tórshavn', 'survey:<id>', 'board:<id>'
create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  target     text not null,
  author     uuid not null references public.profiles (id) on delete cascade,
  parent     uuid references public.comments (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index comments_target on public.comments (target, created_at);
create table public.likes (user_id uuid references public.profiles (id) on delete cascade, target text, created_at timestamptz not null default now(), primary key (user_id, target));
create table public.saves (user_id uuid references public.profiles (id) on delete cascade, target text, created_at timestamptz not null default now(), primary key (user_id, target));
create table public.votes (user_id uuid references public.profiles (id) on delete cascade, survey text, choice smallint not null, created_at timestamptz not null default now(), primary key (user_id, survey));

-- ---------- reports (Apple 1.2, the DSA's notice and action) ----------
create table public.reports (
  id         uuid primary key default gen_random_uuid(),
  reporter   uuid not null references public.profiles (id) on delete cascade,
  target     text not null,                                  -- 'user:<uuid>' or any target above, 'mistake:<what>'
  reason     text not null check (char_length(reason) <= 80),
  note       text not null default '' check (char_length(note) <= 500),
  status     text not null default 'open' check (status in ('open', 'removed', 'kept')),
  answer     text,                                           -- the statement of reasons sent back (DSA Art. 17)
  created_at timestamptz not null default now()
);

-- ---------- chats ----------
create table public.chats (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('direct', 'group', 'solo', 'team')),
  name       text check (char_length(name) <= 40),
  created_at timestamptz not null default now()
);
create table public.chat_members (
  chat_id  uuid references public.chats (id) on delete cascade,
  user_id  uuid references public.profiles (id) on delete cascade,
  muted    boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
create table public.messages (
  id         bigint generated always as identity primary key,
  chat_id    uuid not null references public.chats (id) on delete cascade,
  author     uuid not null references public.profiles (id) on delete cascade,
  body       text not null default '' check (char_length(body) <= 2000),
  media      jsonb,                                         -- a photo, a video, a file, a shared thing
  reactions  jsonb not null default '{}'::jsonb,            -- {"<user uuid>": "👍"}
  created_at timestamptz not null default now()
);
create index messages_chat on public.messages (chat_id, created_at);

-- ---------- Solo and Teams ----------
create table public.verifications (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  provider   text not null,                                 -- 'didit', 'stripe', ...
  over18     boolean not null,
  checked_at timestamptz not null default now()            -- nothing else: no document, no face
);
create table public.solo_profiles (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  bio        text not null default '' check (char_length(bio) <= 120),
  pictures   jsonb not null default '[]'::jsonb,
  answers    jsonb not null default '{}'::jsonb,            -- the eight travel questions
  shows      text not null default 'everyone' check (shows in ('everyone', 'women', 'men', 'nonbinary')),
  radius_km  smallint not null default 25 check (radius_km between 5 and 200),
  age_min    smallint not null default 18 check (age_min >= 18),
  age_max    smallint not null default 99,
  created_at timestamptz not null default now()
);
-- where you are, rounded, good for a day; nobody selects from it (see solo_near)
create table public.solo_shares (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  lat        numeric(6, 2) not null, lon numeric(6, 2) not null,
  town       text not null default '',
  expires_at timestamptz not null default now() + interval '24 hours'
);
create function public.solo_round() returns trigger language plpgsql as $$
begin
  new.lat := round(new.lat / 0.05) * 0.05;
  new.lon := round(new.lon / 0.05) * 0.05;
  new.expires_at := least(new.expires_at, now() + interval '24 hours');
  return new;
end $$;
create trigger solo_shares_round before insert or update on public.solo_shares for each row execute function public.solo_round();
-- planning ahead: a booking or the agreement signed in the app
create table public.solo_plans (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  lat        numeric(6, 2) not null, lon numeric(6, 2) not null,
  from_date  date not null, to_date date not null check (to_date >= from_date),
  proof      text,                                          -- the booking's reference, never the booking itself
  agreed_at  timestamptz,
  check (proof is not null or agreed_at is not null)
);
create table public.teams (
  id         uuid primary key default gen_random_uuid(),
  owner      uuid not null references public.profiles (id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  know       text not null default '',                      -- how they know each other
  pay        text not null default '',                      -- how they split the cost
  created_at timestamptz not null default now()
);
create table public.team_members (
  team_id uuid references public.teams (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete cascade,
  primary key (team_id, user_id)
);
-- pass, save or connect, on a person ('user:<uuid>') or a team ('team:<uuid>')
create table public.solo_actions (
  actor      uuid references public.profiles (id) on delete cascade,
  target     text not null check (target ~ '^(user|team):'),
  action     text not null check (action in ('pass', 'save', 'connect')),
  created_at timestamptz not null default now(),
  primary key (actor, target)
);

-- ---------- notifications ----------
create table public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,                                 -- 'like', 'reply', 'follow', 'request', 'solo_match', ...
  body       jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user on public.notifications (user_id, created_at desc);

-- =====================================================================
-- who can see and do what
-- =====================================================================
create function public.is_friend(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from follows where follower = a and followee = b and status = 'accepted')
     and exists (select 1 from follows where follower = b and followee = a and status = 'accepted');
$$;
create function public.blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a));
$$;
create function public.in_chat(c uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members where chat_id = c and user_id = auth.uid());
$$;
-- asked through functions so the two policies on things and thing_editors do not read each other
create function public.edits_thing(t uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from thing_editors where thing_id = t and user_id = auth.uid());
$$;
create function public.owns_thing(t uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from things where id = t and owner = auth.uid());
$$;

alter table public.profiles enable row level security;
create policy "profiles are read by the signed in" on public.profiles for select to authenticated using (not public.blocked_between(id, auth.uid()));
create policy "you make your own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "you change your own profile" on public.profiles for update to authenticated using (id = auth.uid());
create policy "you delete your own account" on public.profiles for delete to authenticated using (id = auth.uid());

alter table public.follows enable row level security;
create policy "follows are visible" on public.follows for select to authenticated using (true);
create policy "you follow" on public.follows for insert to authenticated with check (follower = auth.uid() and not public.blocked_between(follower, followee));
create policy "you unfollow, or turn down a request" on public.follows for delete to authenticated using (follower = auth.uid() or followee = auth.uid());
create policy "you accept a request" on public.follows for update to authenticated using (followee = auth.uid());

alter table public.blocks enable row level security;
create policy "your blocks" on public.blocks for all to authenticated using (blocker = auth.uid()) with check (blocker = auth.uid());

alter table public.stamps enable row level security;
create policy "stamps are read by the signed in" on public.stamps for select to authenticated using (not public.blocked_between(user_id, auth.uid()));
create policy "your stamps" on public.stamps for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.wishes enable row level security;
create policy "wishes are read by the signed in" on public.wishes for select to authenticated using (not public.blocked_between(user_id, auth.uid()));
create policy "your wishes" on public.wishes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.pins enable row level security;
create policy "your pins" on public.pins for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.things enable row level security;
create policy "things you may see" on public.things for select to authenticated using (
  owner = auth.uid()
  or public.edits_thing(id)
  or (visibility = 'everyone' and not public.blocked_between(owner, auth.uid()))
  or (visibility = 'friends' and public.is_friend(owner, auth.uid())));
create policy "you make things" on public.things for insert to authenticated with check (owner = auth.uid());
create policy "you and your editors change things" on public.things for update to authenticated using (
  owner = auth.uid() or public.edits_thing(id));
create policy "you delete your things" on public.things for delete to authenticated using (owner = auth.uid());
alter table public.thing_editors enable row level security;
create policy "editors are visible to them and the owner" on public.thing_editors for select to authenticated using (
  user_id = auth.uid() or public.owns_thing(thing_id));
create policy "the owner picks editors" on public.thing_editors for all to authenticated using (public.owns_thing(thing_id))
  with check (public.owns_thing(thing_id));

alter table public.posts enable row level security;
create policy "posts are read by the signed in" on public.posts for select to authenticated using (not public.blocked_between(author, auth.uid()));
create policy "your posts" on public.posts for all to authenticated using (author = auth.uid()) with check (author = auth.uid());

alter table public.comments enable row level security;
create policy "comments are read by the signed in" on public.comments for select to authenticated using (not public.blocked_between(author, auth.uid()));
create policy "you comment" on public.comments for insert to authenticated with check (author = auth.uid());
create policy "you delete your comments" on public.comments for delete to authenticated using (author = auth.uid());

alter table public.likes enable row level security;
create policy "likes are counted by all" on public.likes for select to authenticated using (true);
create policy "your likes" on public.likes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.saves enable row level security;
create policy "your saves" on public.saves for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.votes enable row level security;
create policy "votes are counted by all" on public.votes for select to authenticated using (true);
create policy "your votes" on public.votes for insert to authenticated with check (user_id = auth.uid());

alter table public.reports enable row level security;
create policy "you report" on public.reports for insert to authenticated with check (reporter = auth.uid());
create policy "you see your own reports and their answers" on public.reports for select to authenticated using (reporter = auth.uid());

alter table public.chats enable row level security;
create policy "members see their chats" on public.chats for select to authenticated using (public.in_chat(id));
alter table public.chat_members enable row level security;
create policy "members see who is in their chats" on public.chat_members for select to authenticated using (public.in_chat(chat_id));
create policy "you leave a chat" on public.chat_members for delete to authenticated using (user_id = auth.uid());
create policy "you mute a chat" on public.chat_members for update to authenticated using (user_id = auth.uid());
alter table public.messages enable row level security;
create policy "members read messages" on public.messages for select to authenticated using (public.in_chat(chat_id));
create policy "members write messages" on public.messages for insert to authenticated with check (author = auth.uid() and public.in_chat(chat_id));
create policy "members react" on public.messages for update to authenticated using (public.in_chat(chat_id));

alter table public.verifications enable row level security;
create policy "you see your own check" on public.verifications for select to authenticated using (user_id = auth.uid());
-- written only by the ID-check webhook, with the service key (no insert policy on purpose)

alter table public.solo_profiles enable row level security;
create policy "verified people see solo profiles" on public.solo_profiles for select to authenticated using (
  user_id = auth.uid() or (exists (select 1 from verifications v where v.user_id = auth.uid() and v.over18)
                           and not public.blocked_between(user_id, auth.uid())));
create policy "your solo profile" on public.solo_profiles for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.solo_shares enable row level security;
create policy "you share where you are" on public.solo_shares for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.solo_plans enable row level security;
create policy "your plans ahead" on public.solo_plans for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter table public.teams enable row level security;
create policy "teams are seen by the verified" on public.teams for select to authenticated using (
  owner = auth.uid() or exists (select 1 from verifications v where v.user_id = auth.uid() and v.over18));
create policy "your team" on public.teams for all to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
alter table public.team_members enable row level security;
create policy "team members are seen by the verified" on public.team_members for select to authenticated using (
  exists (select 1 from verifications v where v.user_id = auth.uid() and v.over18));
create policy "the owner fills the team" on public.team_members for all to authenticated using (
  exists (select 1 from teams t where t.id = team_id and t.owner = auth.uid()))
  with check (exists (select 1 from teams t where t.id = team_id and t.owner = auth.uid()));
alter table public.solo_actions enable row level security;
create policy "your solo actions" on public.solo_actions for all to authenticated using (actor = auth.uid()) with check (actor = auth.uid());

alter table public.notifications enable row level security;
create policy "your notifications" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "you mark them read" on public.notifications for update to authenticated using (user_id = auth.uid());

-- =====================================================================
-- Solo: who is near you, never where they are
-- =====================================================================
-- People and teams within your radius, from where you shared (or plan to be). It returns
-- the distance rounded to 5 km and never a position. Only for someone verified and over 18
-- who has shared in the last day or has a plan with proof.
create function public.solo_near() returns table (who uuid, km integer)
language plpgsql stable security definer set search_path = public as $$
declare me_lat numeric; me_lon numeric; r smallint;
begin
  if not exists (select 1 from verifications where user_id = auth.uid() and over18) then return; end if;
  select s.lat, s.lon into me_lat, me_lon from solo_shares s where s.user_id = auth.uid() and s.expires_at > now();
  if me_lat is null then
    select p.lat, p.lon into me_lat, me_lon from solo_plans p where p.user_id = auth.uid() and p.to_date >= current_date;
  end if;
  if me_lat is null then return; end if;
  select coalesce(sp.radius_km, 25) into r from solo_profiles sp where sp.user_id = auth.uid();
  r := coalesce(r, 25);
  return query
    select s.user_id,
           (round(6371 * acos(least(1, greatest(-1,
              sin(radians(me_lat)) * sin(radians(s.lat)) + cos(radians(me_lat)) * cos(radians(s.lat)) * cos(radians(s.lon - me_lon))))) / 5) * 5)::integer
    from solo_shares s
    join verifications v on v.user_id = s.user_id and v.over18
    where s.expires_at > now() and s.user_id <> auth.uid()
      and not public.blocked_between(s.user_id, auth.uid())
      and not exists (select 1 from solo_actions a where a.actor = auth.uid() and a.target = 'user:' || s.user_id and a.action = 'pass')
      and 6371 * acos(least(1, greatest(-1,
            sin(radians(me_lat)) * sin(radians(s.lat)) + cos(radians(me_lat)) * cos(radians(s.lat)) * cos(radians(s.lon - me_lon))))) <= r;
end $$;

-- both said connect: a chat opens for the two of them, and both are told
create function public.solo_match() returns trigger language plpgsql security definer set search_path = public as $$
declare other uuid; c uuid;
begin
  if new.action <> 'connect' or new.target !~ '^user:' then return new; end if;
  other := substring(new.target from 6)::uuid;
  if exists (select 1 from solo_actions where actor = other and target = 'user:' || new.actor and action = 'connect') then
    insert into chats (kind) values ('solo') returning id into c;
    insert into chat_members (chat_id, user_id) values (c, new.actor), (c, other);
    insert into notifications (user_id, kind, body) values
      (new.actor, 'solo_match', jsonb_build_object('with', other, 'chat', c)),
      (other, 'solo_match', jsonb_build_object('with', new.actor, 'chat', c));
  end if;
  return new;
end $$;
create trigger solo_actions_match after insert or update on public.solo_actions for each row execute function public.solo_match();
