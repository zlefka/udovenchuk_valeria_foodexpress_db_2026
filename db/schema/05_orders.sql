-- Заказы, позиции заказов, оплаты и отзывы.

begin;

-- BR-7.1–7.13. Заказ и его суммы.
create table udovenchuk_food."order" (
    order_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null,
    restaurant_id uuid not null,
    courier_id uuid not null,
    address_id uuid not null,
    order_timestamp timestamp not null default localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(14, 2) not null,
    commission numeric(14, 2)
        generated always as (round(order_amount * 0.10, 2)) stored not null,
    total_amount numeric(14, 2)
        generated always as (order_amount + round(order_amount * 0.10, 2)) stored not null,
    status udovenchuk_food.order_status not null,
    pay_status udovenchuk_food.order_pay_status not null default 'ожидает',
    description text not null,
    constraint order_client_fk
        foreign key (client_id) references udovenchuk_food.client (client_id),
    constraint order_restaurant_fk
        foreign key (restaurant_id) references udovenchuk_food.restaurant (restaurant_id),
    constraint order_courier_fk
        foreign key (courier_id) references udovenchuk_food.courier (courier_id),
    constraint order_address_fk
        foreign key (address_id) references udovenchuk_food.address (address_id),
    -- Пара клиента и адреса должна быть в таблице привязок.
    constraint order_client_address_fk
        foreign key (client_id, address_id)
        references udovenchuk_food.client_address (client_id, address_id),
    constraint order_amount_range
        check (order_amount >= 0 and order_amount <> 'NaN'::numeric),
    constraint order_total_minimum check (total_amount >= 1000),
    constraint order_delivery_required
        check (status <> 'доставлен' or delivery_timestamp is not null),
    constraint order_delivery_dates check (delivery_timestamp >= order_timestamp)
);

-- BR-7.14–7.16. Одно блюдо может занимать только одну позицию заказа.
create table udovenchuk_food.order_structure (
    order_id uuid not null,
    product_id uuid not null,
    quantity numeric(12, 3) not null,

    constraint order_structure_pk primary key (order_id, product_id),
    constraint order_structure_order_fk
        foreign key (order_id) references udovenchuk_food."order" (order_id),
    constraint order_structure_product_fk
        foreign key (product_id) references udovenchuk_food.product (product_id),
    constraint order_structure_quantity_positive
        check (quantity > 0 and quantity <> 'NaN'::numeric)
);

-- BR-8.1–8.6. Отдельная строка для каждой попытки оплаты.
create table udovenchuk_food.payment (
    payment_id uuid primary key default exts.uuid_generate_v4(),
    order_id uuid not null,
    payment_type udovenchuk_food.payment_type not null,
    amount numeric(14, 2) not null,
    transaction_reference varchar(200) not null,
    transaction_timestamp timestamp not null default localtimestamp,
    status udovenchuk_food.payment_status not null,

    constraint payment_order_fk
        foreign key (order_id) references udovenchuk_food."order" (order_id),
    constraint payment_transaction_reference_unique unique (transaction_reference),
    constraint payment_transaction_reference_not_blank
        check (btrim(transaction_reference) <> ''),
    constraint payment_amount_range check (amount >= 0 and amount <> 'NaN'::numeric)
);

-- Уникальность действует только для успешных попыток.
create unique index payment_one_success_idx
    on udovenchuk_food.payment (order_id)
    where status = 'успех';

-- BR-9.1–9.5. Отзыв связан с заказом, автором и объектом отзыва.
create table udovenchuk_food.review (
    review_id uuid primary key default exts.uuid_generate_v4(),
    client_id uuid not null,
    order_id uuid not null,
    entity_type udovenchuk_food.review_entity_type not null,
    entity_id uuid not null,
    description text not null,
    photo_url text,
    rating numeric(3, 2) not null,
    review_timestamp timestamp not null default localtimestamp,

    constraint review_client_fk
        foreign key (client_id) references udovenchuk_food.client (client_id),
    constraint review_order_fk
        foreign key (order_id) references udovenchuk_food."order" (order_id),
    constraint review_order_entity_unique unique (order_id, entity_type, entity_id),
    constraint review_rating_range check (rating between 1 and 5)
);

commit;

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'udovenchuk_food'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
