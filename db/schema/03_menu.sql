-- Рестораны, категории и блюда.

begin;

-- BR-3.3, BR-4.1–4.5: ресторан и его единственный адрес.
create table udovenchuk_food.restaurant (
    restaurant_id uuid primary key default exts.uuid_generate_v4(),
    restaurant_name varchar(200) not null,
    address_id uuid not null,
    description text not null,
    work_start time not null,
    work_end time not null,
    company_details text not null,
    -- BR-9.7: пока нет отзывов, рейтинг отсутствует.
    rating numeric(3, 2),
    status udovenchuk_food.restaurant_status not null,
    constraint restaurant_address_unique unique (address_id),
    constraint restaurant_address_fk
        foreign key (address_id) references udovenchuk_food.address (address_id),
    constraint restaurant_name_not_blank check (btrim(restaurant_name) <> ''),
    constraint restaurant_work_hours check (work_end > work_start),
    constraint restaurant_rating_range check (rating between 0 and 5)
);

-- BR-5.7: справочник категорий блюд.
create table udovenchuk_food.product_category (
    product_category_id uuid primary key default exts.uuid_generate_v4(),
    product_category_name varchar(100) not null,

    constraint product_category_name_not_blank
        check (btrim(product_category_name) <> '')
);

-- BR-5.1–5.6: каждое блюдо относится к ресторану и категории.
create table udovenchuk_food.product (
    product_id uuid primary key default exts.uuid_generate_v4(),
    product_name varchar(200) not null,
    product_category_id uuid not null,
    restaurant_id uuid not null,
    price numeric(14, 2) not null,
    description text not null,
    photo_url text,
    rating numeric(3, 2),
    status udovenchuk_food.product_status not null,
    constraint product_category_fk
        foreign key (product_category_id)
        references udovenchuk_food.product_category (product_category_id),
    constraint product_restaurant_fk
        foreign key (restaurant_id)
        references udovenchuk_food.restaurant (restaurant_id),
    constraint product_name_not_blank check (btrim(product_name) <> ''),
    -- NaN не является обычной числовой ценой и отдельно запрещено.
    constraint product_price_range check (price >= 0 and price <> 'NaN'::numeric),
    constraint product_rating_range check (rating between 0 and 5)
);

commit;

-- проверка создания таблиц
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'udovenchuk_food'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
