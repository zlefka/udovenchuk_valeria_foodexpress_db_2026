begin;

create schema udovenchuk_food;

-- BR-4.3: статус ресторана.
create type udovenchuk_food.restaurant_status as enum (
    'активен', 'неактивен'
);

-- BR-5.5: статус блюда.
create type udovenchuk_food.product_status as enum (
    'доступно', 'нет_в_наличии', 'архив'
);

-- BR-6.2: статус курьера.
create type udovenchuk_food.courier_status as enum (
    'свободен', 'занят', 'на_доставке', 'уволен'
);

-- BR-7.7: статус заказа.
create type udovenchuk_food.order_status as enum (
    'создан', 'готовится', 'в_доставке', 'доставлен', 'отменён'
);

-- BR-7.9: общий статус оплаты заказа.
create type udovenchuk_food.order_pay_status as enum (
    'ожидает', 'оплачен', 'ошибка'
);

-- BR-8.2: статус отдельной попытки оплаты.
create type udovenchuk_food.payment_status as enum (
    'успех', 'ошибка', 'в_обработке'
);

-- BR-8.2: способ оплаты.
create type udovenchuk_food.payment_type as enum (
    'карта', 'наличные', 'безнал'
);

-- BR-9.1: объект, на который оставлен отзыв.
create type udovenchuk_food.review_entity_type as enum (
    'блюдо', 'ресторан', 'заказ'
);

commit;



-- проверка создания enumов
-- SELECT t.typname
-- FROM pg_type t
-- JOIN pg_namespace n ON n.oid = t.typnamespace
-- WHERE n.nspname = 'udovenchuk_food'
--   AND t.typtype = 'e'
-- ORDER BY t.typname;