-- CALL udovenchuk_food.erase_test_data() удаляет все строки из 12 таблиц проекта.

create or replace procedure udovenchuk_food.erase_test_data()
as $$
begin
    -- Сначала удаляем записи, которые ссылаются на заказы и курьеров.
    delete from udovenchuk_food.review;
    delete from udovenchuk_food.payment;
    delete from udovenchuk_food.order_structure;
    delete from udovenchuk_food.courier_pay;

    -- Теперь можно удалить заказы, привязки адресов, блюда и рестораны.
    delete from udovenchuk_food."order";
    delete from udovenchuk_food.client_address;
    delete from udovenchuk_food.product;
    delete from udovenchuk_food.restaurant;

    -- На эти таблицы больше нет ссылок из других записей.
    delete from udovenchuk_food.client;
    delete from udovenchuk_food.courier;
    delete from udovenchuk_food.product_category;
    delete from udovenchuk_food.address;
end;
$$ language plpgsql;
