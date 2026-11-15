-- FOOD-109. Выполнить от администратора после восстановления схемы.
-- Роль inspector используется для проверки учебной базы.

begin;

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'inspector') then
        create role inspector login password 'NetoSQL2025';
    end if;
end;
$$ language plpgsql;

grant all privileges on schema udovenchuk_food to inspector;
grant usage on schema exts, information_schema, pg_catalog to inspector;
grant execute on function exts.uuid_generate_v4() to inspector;

grant select, insert, update, delete on all tables in schema udovenchuk_food to inspector;
grant execute on all routines in schema udovenchuk_food to inspector;

commit;
