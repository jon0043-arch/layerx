-- Run in the Supabase SQL editor. All access is through the protected Next.js API.
create extension if not exists pgcrypto;
create table if not exists public.layers (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 2 and 60),
  message text not null check (char_length(message) between 2 and 280),
  creator text not null default 'ANONYMOUS' check (char_length(creator) between 1 and 32),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  status text not null default 'public' check (status in ('public','hidden')),
  created_at timestamptz not null default now()
);
create index if not exists layers_geo_idx on public.layers(latitude, longitude);
create index if not exists layers_public_created_idx on public.layers(status, created_at desc);
alter table public.layers enable row level security;
-- Intentionally no public table policies. Never expose the service-role key to browsers.
