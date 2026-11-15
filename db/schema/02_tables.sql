begin;

-- BR-2.1–2.3: регистрационные данные клиента.
create table udovenchuk_food.client (
    client_id uuid primary key default exts.uuid_generate_v4(),
    login varchar(100) not null,
    password varchar(32) not null,
    phone_number varchar(20) not null,

    constraint client_login_unique unique (login),
    constraint client_phone_unique unique (phone_number),
    constraint client_login_not_blank check (btrim(login) <> ''),
    constraint client_phone_not_blank check (btrim(phone_number) <> ''),
    -- MD5 записывается как 32 шестнадцатеричных символа.
    constraint client_password_md5 check (password ~ '^[0-9a-f]{32}$')
);

-- BR-3.1–3.2: улица и дом обязательны, квартира может отсутствовать.
create table udovenchuk_food.address (
    address_id uuid primary key default exts.uuid_generate_v4(),
    street varchar(200) not null,
    house_number varchar(20) not null,
    apartment_office varchar(20),

    -- Одинаковый адрес хранится одной строкой, в том числе без квартиры.
    constraint address_location_unique
        unique nulls not distinct (street, house_number, apartment_office),
    constraint address_street_not_blank check (btrim(street) <> ''),
    constraint address_house_not_blank check (btrim(house_number) <> ''),
    constraint address_apartment_not_blank
        check (apartment_office is null or btrim(apartment_office) <> '')
);

-- BR-2.4–2.5: связь многих клиентов со многими адресами.
create table udovenchuk_food.client_address (
    client_id uuid not null,
    address_id uuid not null,

    -- Одна пара «клиент — адрес» не может повторяться.
    constraint client_address_pk primary key (client_id, address_id),
    constraint client_address_client_fk
        foreign key (client_id) references udovenchuk_food.client (client_id),
    constraint client_address_address_fk
        foreign key (address_id) references udovenchuk_food.address (address_id)
);

commit;


-- проверка создания таблиц
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'udovenchuk_food'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

