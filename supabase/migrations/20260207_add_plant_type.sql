alter table public.plants
add column if not exists plant_type text;

update public.plants
set plant_type = case
  when lower(name) like '%peper%' or lower(name) like '%peperonc%' or lower(name) like '%pepper%' or lower(name) like '%chili%' then 'peperoncino'
  when lower(name) like '%sansevieria%' or lower(name) like '%sanseveria%' or lower(name) like '%snake%' then 'sansevieria'
  when lower(name) like '%bonsai%' then 'bonsai'
  when lower(name) like '%cactus%' then 'cactus'
  else 'generic'
end
where plant_type is null;

alter table public.plants
alter column plant_type set default 'generic';

alter table public.plants
alter column plant_type set not null;

alter table public.plants
drop constraint if exists plants_plant_type_check;

alter table public.plants
add constraint plants_plant_type_check
check (plant_type in ('generic', 'peperoncino', 'sansevieria', 'bonsai', 'cactus'));
