create extension if not exists pgcrypto;

create type public.content_status as enum ('draft', 'review', 'published', 'archived');
create type public.rights_status as enum ('pending', 'approved', 'rejected', 'expired');
create type public.rights_basis as enum ('owned', 'licensed', 'public_domain', 'open_license');
create type public.asset_kind as enum ('video', 'audio', 'captions', 'transcript', 'artwork');
create type public.lesson_status as enum ('draft', 'review', 'published', 'archived');
create type public.entitlement_status as enum ('trialing', 'active', 'past_due', 'canceled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Aluno',
  preferred_locale text not null default 'pt-BR',
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  title text not null,
  description text not null default '',
  creator text not null,
  source_country text check (source_country is null or source_country ~ '^[A-Z]{2}$'),
  primary_language text not null default 'en',
  difficulty text not null check (difficulty in ('beginner', 'intermediate', 'advanced')),
  theme text not null,
  duration_seconds numeric(10, 3) not null check (duration_seconds > 0),
  artwork_path text,
  status public.content_status not null default 'draft',
  published_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'published' and published_at is not null) or status <> 'published')
);

create table public.content_rights (
  content_id uuid primary key references public.content_items(id) on delete cascade,
  basis public.rights_basis not null,
  status public.rights_status not null default 'pending',
  rights_holder text not null,
  rights_contact text,
  source_url text not null,
  source_file_sha256 text not null check (source_file_sha256 ~ '^[0-9a-f]{64}$'),
  license_name text,
  license_url text,
  attribution_text text,
  evidence_path text not null,
  notes text not null default '',
  allowed_territories text[] not null default '{}',
  commercial_use boolean not null default false,
  derivative_works boolean not null default false,
  streaming_allowed boolean not null default false,
  offline_download_allowed boolean not null default false,
  translation_allowed boolean not null default false,
  valid_from date,
  valid_through date,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(allowed_territories) > 0),
  check (valid_through is null or valid_from is null or valid_through >= valid_from),
  check ((status = 'approved' and reviewed_at is not null and commercial_use) or status <> 'approved')
);

create table public.content_assets (
  id uuid primary key default gen_random_uuid(),
  content_id uuid not null references public.content_items(id) on delete cascade,
  kind public.asset_kind not null,
  storage_bucket text not null default 'lesson-media',
  storage_path text not null,
  language_code text,
  mime_type text not null,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  checksum_sha256 text,
  duration_seconds numeric(10, 3) check (duration_seconds is null or duration_seconds > 0),
  created_at timestamptz not null default now(),
  unique (storage_bucket, storage_path)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  content_id uuid not null references public.content_items(id) on delete cascade,
  title text not null,
  version integer not null default 1 check (version > 0),
  status public.lesson_status not null default 'draft',
  ai_model text,
  segmentation_prompt_version text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (content_id, version),
  check ((status = 'published' and reviewed_at is not null) or status <> 'published')
);

create table public.lesson_segments (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  position integer not null check (position >= 0),
  start_seconds numeric(10, 3) not null check (start_seconds >= 0),
  end_seconds numeric(10, 3) not null,
  text text not null,
  translation text not null default '',
  difficulty text check (difficulty is null or difficulty in ('beginner', 'intermediate', 'advanced')),
  created_at timestamptz not null default now(),
  unique (lesson_id, position),
  check (end_seconds > start_seconds)
);

create table public.user_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  content_id uuid not null references public.content_items(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete set null,
  segment_position integer not null default 0 check (segment_position >= 0),
  completed_percent numeric(5, 2) not null default 0 check (completed_percent between 0 and 100),
  seconds_studied integer not null default 0 check (seconds_studied >= 0),
  state jsonb not null default '{}'::jsonb,
  last_studied_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, content_id)
);

create table public.user_library (
  user_id uuid not null references auth.users(id) on delete cascade,
  content_id uuid not null references public.content_items(id) on delete cascade,
  is_favorite boolean not null default false,
  added_at timestamptz not null default now(),
  primary key (user_id, content_id)
);

create table public.user_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free', 'pro', 'internal')),
  status public.entitlement_status not null default 'active',
  ai_monthly_limit integer not null default 20 check (ai_monthly_limit >= 0),
  current_period_start timestamptz not null default date_trunc('month', now()),
  current_period_end timestamptz not null default date_trunc('month', now()) + interval '1 month',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (current_period_end > current_period_start)
);

create table public.ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feature text not null,
  request_id text not null unique,
  input_units integer not null default 0 check (input_units >= 0),
  output_units integer not null default 0 check (output_units >= 0),
  estimated_cost_usd numeric(12, 6) not null default 0 check (estimated_cost_usd >= 0),
  created_at timestamptz not null default now()
);

create index content_items_published_idx on public.content_items (theme, difficulty, published_at desc)
  where status = 'published';
create index content_assets_content_kind_idx on public.content_assets (content_id, kind);
create index lessons_content_status_idx on public.lessons (content_id, status, version desc);
create index lesson_segments_lesson_position_idx on public.lesson_segments (lesson_id, position);
create index user_progress_recent_idx on public.user_progress (user_id, last_studied_at desc);
create index ai_usage_events_period_idx on public.ai_usage_events (user_id, created_at desc);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

create function public.can_access_content(target_content_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.content_items as content
    join public.content_rights as rights on rights.content_id = content.id
    where content.id = target_content_id
      and content.status = 'published'
      and rights.status = 'approved'
      and rights.commercial_use
      and rights.streaming_allowed
      and (rights.valid_from is null or rights.valid_from <= current_date)
      and (rights.valid_through is null or rights.valid_through >= current_date)
      and exists (
        select 1
        from public.profiles as profile
        where profile.id = auth.uid()
          and profile.country_code = any(rights.allowed_territories)
      )
  );
$$;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, country_code)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1), 'Aluno'),
    case
      when upper(coalesce(new.raw_user_meta_data ->> 'country_code', '')) ~ '^[A-Z]{2}$'
        then upper(new.raw_user_meta_data ->> 'country_code')
      else null
    end
  );

  insert into public.user_entitlements (user_id)
  values (new.id);

  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger content_items_set_updated_at before update on public.content_items
for each row execute function public.set_updated_at();
create trigger content_rights_set_updated_at before update on public.content_rights
for each row execute function public.set_updated_at();
create trigger lessons_set_updated_at before update on public.lessons
for each row execute function public.set_updated_at();
create trigger user_progress_set_updated_at before update on public.user_progress
for each row execute function public.set_updated_at();
create trigger user_entitlements_set_updated_at before update on public.user_entitlements
for each row execute function public.set_updated_at();

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.content_items enable row level security;
alter table public.content_rights enable row level security;
alter table public.content_assets enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_segments enable row level security;
alter table public.user_progress enable row level security;
alter table public.user_library enable row level security;
alter table public.user_entitlements enable row level security;
alter table public.ai_usage_events enable row level security;

create policy profiles_select_own_or_admin on public.profiles
for select to authenticated
using ((select auth.uid()) = id or public.is_admin());
create policy profiles_update_own_or_admin on public.profiles
for update to authenticated
using ((select auth.uid()) = id or public.is_admin())
with check ((select auth.uid()) = id or public.is_admin());

create policy content_items_read_available on public.content_items
for select to authenticated
using (public.can_access_content(id));
create policy content_items_admin_all on public.content_items
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy content_rights_admin_all on public.content_rights
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy content_assets_admin_all on public.content_assets
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy lessons_read_available on public.lessons
for select to authenticated
using (status = 'published' and public.can_access_content(content_id));
create policy lessons_admin_all on public.lessons
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy lesson_segments_read_available on public.lesson_segments
for select to authenticated
using (
  exists (
    select 1 from public.lessons
    where lessons.id = lesson_segments.lesson_id
      and lessons.status = 'published'
      and public.can_access_content(lessons.content_id)
  )
);
create policy lesson_segments_admin_all on public.lesson_segments
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy user_progress_select_own on public.user_progress
for select to authenticated
using ((select auth.uid()) = user_id);
create policy user_progress_insert_own on public.user_progress
for insert to authenticated
with check ((select auth.uid()) = user_id and public.can_access_content(content_id));
create policy user_progress_update_own on public.user_progress
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id and public.can_access_content(content_id));
create policy user_progress_delete_own on public.user_progress
for delete to authenticated
using ((select auth.uid()) = user_id);

create policy user_library_select_own on public.user_library
for select to authenticated
using ((select auth.uid()) = user_id);
create policy user_library_insert_own on public.user_library
for insert to authenticated
with check ((select auth.uid()) = user_id and public.can_access_content(content_id));
create policy user_library_update_own on public.user_library
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id and public.can_access_content(content_id));
create policy user_library_delete_own on public.user_library
for delete to authenticated
using ((select auth.uid()) = user_id);

create policy user_entitlements_select_own on public.user_entitlements
for select to authenticated
using ((select auth.uid()) = user_id);
create policy user_entitlements_admin_all on public.user_entitlements
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy ai_usage_events_select_own on public.ai_usage_events
for select to authenticated
using ((select auth.uid()) = user_id);
create policy ai_usage_events_admin_all on public.ai_usage_events
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke execute on function public.set_updated_at() from public;
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.is_admin() from public;
revoke execute on function public.can_access_content(uuid) from public;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_access_content(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'lesson-media',
    'lesson-media',
    false,
    2147483648,
    array['video/mp4', 'video/quicktime', 'audio/mpeg', 'audio/mp4', 'text/vtt', 'application/json']
  ),
  (
    'lesson-artwork',
    'lesson-artwork',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'rights-evidence',
    'rights-evidence',
    false,
    52428800,
    array['application/pdf', 'image/jpeg', 'image/png', 'text/plain']
  )
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

comment on table public.content_rights is 'Private rights evidence and territory approval. Client access is intentionally denied.';
comment on table public.content_assets is 'Private object paths. Clients receive only short-lived signed URLs from the API.';
comment on table public.ai_usage_events is 'Server-written audit trail used to enforce per-user AI limits.';
