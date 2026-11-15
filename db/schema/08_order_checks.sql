-- Цена позиции фиксируется при вставке. У доставленного заказа должна быть успешная оплата.

begin;

-- BR-7.12. Время окончания доставки появляется вместе со статусом «доставлен».
alter table udovenchuk_food."order" drop constraint order_delivery_required;
alter table udovenchuk_food."order"
    add constraint order_delivery_required
        check ((status = 'доставлен') = (delivery_timestamp is not null));

alter table udovenchuk_food.order_structure
    add column unit_price numeric(14, 2)
        constraint order_structure_unit_price_range
        check (unit_price >= 0 and unit_price <> 'NaN'::numeric);

-- Заполняем цену в ранее созданных позициях. Суммы сверяются ниже в этой же транзакции.
update udovenchuk_food.order_structure os
set unit_price = p.price
from udovenchuk_food.product p
where p.product_id = os.product_id
  and os.unit_price is null;

-- Выполняем отложенные проверки от UPDATE до следующего ALTER TABLE.
set constraints udovenchuk_food.order_structure_check_order immediate;

alter table udovenchuk_food.order_structure
    alter column unit_price set not null;

-- При вставке без unit_price берём текущую цену из меню.
create function udovenchuk_food.fill_order_unit_price()
returns trigger as $$
begin
    select p.price
    into new.unit_price
    from udovenchuk_food.product p
    where p.product_id = new.product_id;

    return new;
end;
$$ language plpgsql;

create trigger order_structure_fill_unit_price
before insert on udovenchuk_food.order_structure
for each row
when (new.unit_price is null)
execute function udovenchuk_food.fill_order_unit_price();

create or replace function udovenchuk_food.check_order_integrity(
    checked_order_id uuid,
    attached_product_id uuid default null
)
returns void as $$
declare
    order_client_id uuid;
    order_restaurant_id uuid;
    order_total numeric(14, 2);
    saved_order_amount numeric(14, 2);
    saved_order_status udovenchuk_food.order_status;
    positions_amount numeric;
    calculated_pay_status udovenchuk_food.order_pay_status;
begin
    -- Изменения связанных строк одного заказа проверяются по очереди.
    select o.client_id, o.restaurant_id, o.total_amount, o.order_amount, o.status
    into order_client_id, order_restaurant_id, order_total, saved_order_amount, saved_order_status
    from udovenchuk_food."order" o
    where o.order_id = checked_order_id
    for no key update;

    -- При удалении заказа проверять уже нечего.
    if not found then
        return;
    end if;

    -- При записи позиции создаём новую версию строки блюда.
    -- Параллельная смена ресторана проверит связь с заказом после этой записи.
    if attached_product_id is not null then
        update udovenchuk_food.product
        set restaurant_id = restaurant_id
        where product_id = attached_product_id;
    end if;

    -- BR-7.10 и BR-7.14. Сверяем стоимость блюд по сохранённым ценам.
    select round(sum(os.quantity * os.unit_price), 2)
    into positions_amount
    from udovenchuk_food.order_structure os
    where os.order_id = checked_order_id;

    if positions_amount is null then
        raise exception 'В заказе % нет позиций', checked_order_id;
    end if;

    if saved_order_amount <> positions_amount then
        raise exception 'В заказе % указана стоимость %, а сумма позиций равна %',
            checked_order_id, saved_order_amount, positions_amount;
    end if;

    -- Пока проверяем заказ, ресторан его блюда не может измениться.
    perform p.product_id
    from udovenchuk_food.order_structure os
    join udovenchuk_food.product p on p.product_id = os.product_id
    where os.order_id = checked_order_id
    order by p.product_id
    for share of p;

    -- BR-7.3. Все блюда принадлежат ресторану заказа.
    if exists (
        select 1
        from udovenchuk_food.order_structure os
        join udovenchuk_food.product p on p.product_id = os.product_id
        where os.order_id = checked_order_id
          and p.restaurant_id <> order_restaurant_id
    ) then
        raise exception 'В заказе % есть блюдо из другого ресторана', checked_order_id;
    end if;

    -- BR-8.4. Сумма каждой попытки оплаты равна итогу заказа.
    if exists (
        select 1
        from udovenchuk_food.payment p
        where p.order_id = checked_order_id
          and p.amount <> order_total
    ) then
        raise exception 'Сумма оплаты заказа % должна быть %', checked_order_id, order_total;
    end if;

    -- BR-9.2. Отзыв принадлежит клиенту заказа и относится к его заказу.
    if exists (
        select 1
        from udovenchuk_food.review r
        where r.order_id = checked_order_id
          and (
              r.client_id <> order_client_id
              or (r.entity_type = 'заказ' and r.entity_id <> checked_order_id)
              or (r.entity_type = 'ресторан' and r.entity_id <> order_restaurant_id)
              or (
                  r.entity_type = 'блюдо' and not exists (
                      select 1
                      from udovenchuk_food.order_structure os
                      where os.order_id = r.order_id
                        and os.product_id = r.entity_id
                  )
              )
          )
    ) then
        raise exception 'В заказе % есть отзыв от другого клиента или о другом объекте',
            checked_order_id;
    end if;

    -- BR-8.1 и BR-8.7. Пока заказ не доставлен, оплата может ожидаться или завершиться ошибкой.
    if exists (
        select 1
        from udovenchuk_food.payment p
        where p.order_id = checked_order_id and p.status = 'успех'
    ) then
        calculated_pay_status := 'оплачен';
    elsif exists (
        select 1
        from udovenchuk_food.payment p
        where p.order_id = checked_order_id and p.status = 'в_обработке'
    ) then
        calculated_pay_status := 'ожидает';
    elsif exists (
        select 1
        from udovenchuk_food.payment p
        where p.order_id = checked_order_id
    ) then
        calculated_pay_status := 'ошибка';
    else
        calculated_pay_status := 'ожидает';
    end if;

    -- Индекс из 05 запрещает вторую успешную попытку.
    if saved_order_status = 'доставлен' and calculated_pay_status <> 'оплачен' then
        raise exception 'У доставленного заказа % должна быть одна успешная оплата', checked_order_id;
    end if;

    update udovenchuk_food."order"
    set pay_status = calculated_pay_status
    where order_id = checked_order_id;
end;
$$ language plpgsql;

drop trigger order_check_after_update on udovenchuk_food."order";
create constraint trigger order_check_after_update
after update on udovenchuk_food."order"
deferrable initially deferred
for each row
when (
    old.order_id <> new.order_id
    or old.client_id <> new.client_id
    or old.restaurant_id <> new.restaurant_id
    or old.order_amount <> new.order_amount
    or old.pay_status <> new.pay_status
    or old.status <> new.status
)
execute function udovenchuk_food.check_changed_order();

-- Проверяем, что сохранённые заказы соответствуют новым условиям.
do $$
declare
    existing_order_id uuid;
begin
    for existing_order_id in
        select order_id from udovenchuk_food."order" order by order_id
    loop
        perform udovenchuk_food.check_order_integrity(existing_order_id);
    end loop;
end;
$$ language plpgsql;

commit;

select count(*) as total_positions, count(unit_price) as positions_with_price
from udovenchuk_food.order_structure;
