alter table public.offers
  add column customer_id uuid references public.customers (id),
  add column starts_on date,
  add column ends_on date;

alter table public.offers
  add constraint offers_date_range check (ends_on is null or ends_on >= starts_on);

alter table public.offers
  add constraint offers_required_details check (
    customer_id is not null and starts_on is not null and ends_on is not null
  ) not valid;

create function public.validate_offer_assignment()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.customers
    where id = new.customer_id
      and team_id = new.team_id
  ) then
    raise exception 'Offer and customer must belong to the same team';
  end if;

  if not exists (
    select 1
    from public.projects
    where id = new.project_id
      and customer_id = new.customer_id
      and team_id = new.team_id
  ) then
    raise exception 'Offer project must belong to the selected customer and team';
  end if;

  if not exists (
    select 1
    from public.employee_assignments
    where employee_id = new.employee_id
      and project_id = new.project_id
      and team_id = new.team_id
      and starts_on <= new.starts_on
      and (ends_on is null or ends_on >= new.ends_on)
  ) then
    raise exception 'Offer period must be within an assignment of the selected employee';
  end if;

  return new;
end;
$$;

create trigger offers_valid_assignment before insert or update on public.offers
for each row execute function public.validate_offer_assignment();
