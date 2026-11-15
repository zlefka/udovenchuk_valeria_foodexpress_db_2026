-- Курьеры и ежемесячные выплаты.
begin;

-- BR-6.1–6.5. Данные о курьере и его текущий коэффициент.
create table udovenchuk_food.courier (
    courier_id uuid primary key default exts.uuid_generate_v4(),
    fio varchar(300) not null,
    phone_number varchar(20) not null,
    status udovenchuk_food.courier_status not null,
    hire_date date not null,
    dismissal_date date,
    coefficient numeric(3, 2) not null default 0.10,

    constraint courier_fio_not_blank check (btrim(fio) <> ''),
    constraint courier_phone_not_blank check (btrim(phone_number) <> ''),
    constraint courier_dismissal_required
        check (status <> 'уволен' or dismissal_date is not null),
    constraint courier_employment_dates check (dismissal_date >= hire_date),
    constraint courier_coefficient_range check (coefficient between 0.10 and 0.50)
);

-- BR-10.1–10.4. Одна выплата на курьера за каждый месяц.
create table udovenchuk_food.courier_pay (
    year integer not null,
    month integer not null,
    courier_id uuid not null,
    amount numeric(14, 2) not null,
    coefficient_used numeric(3, 2) not null,

    constraint courier_pay_pk primary key (year, month, courier_id),
    constraint courier_pay_courier_fk
        foreign key (courier_id) references udovenchuk_food.courier (courier_id),
    constraint courier_pay_year_range check (year between 1 and 9999),
    constraint courier_pay_month_range check (month between 1 and 12),
    constraint courier_pay_amount_range check (amount >= 0 and amount <> 'NaN'::numeric),
    constraint courier_pay_coefficient_range check (coefficient_used between 0.10 and 0.50)
);

commit;

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'udovenchuk_food'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
