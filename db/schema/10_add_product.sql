-- FOOD-104. Выполнение файла создаёт процедуру добавления блюда.

create or replace procedure udovenchuk_food.add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status udovenchuk_food.product_status,
    p_description text,
    p_photo_url text default null
)
as $$
begin
    -- product_id PostgreSQL создаёт автоматически по DEFAULT из таблицы product.
    insert into udovenchuk_food.product (
        restaurant_id, product_category_id, product_name, price,
        rating, status, description, photo_url
    )
    values (
        p_restaurant_id, p_product_category_id, p_name, p_price,
        p_rating, p_status, p_description, p_photo_url
    );
exception
    when foreign_key_violation then
        raise exception 'Ресторан или категория блюда не существуют';
    when check_violation then
        raise exception 'Проверь название, цену и рейтинг блюда. Название должно быть заполнено, цена от 0, рейтинг от 0 до 5.';
end;
$$ language plpgsql;
