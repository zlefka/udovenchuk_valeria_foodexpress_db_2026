-- Новый заказ и его позиции записываются в одной транзакции.

begin;

-- Проверка одного заказа и пересчёт его статуса оплаты.
create function udovenchuk_food.check_order_integrity(
    checked_order_id uuid,
    attached_product_id uuid default null
)
returns void as $$
declare
    order_client_id uuid;
    order_restaurant_id uuid;
    order_total numeric(14, 2);
    calculated_pay_status udovenchuk_food.order_pay_status;
begin
    -- Изменения связанных строк одного заказа проверяются по очереди.
    select o.client_id, o.restaurant_id, o.total_amount
    into order_client_id, order_restaurant_id, order_total
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

    -- BR-7.14. В сохранённом заказе есть хотя бы одна позиция.
    if not exists (
        select 1
        from udovenchuk_food.order_structure os
        where os.order_id = checked_order_id
    ) then
        raise exception 'В заказе % нет позиций', checked_order_id;
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

    -- BR-8.7. Успех важнее обработки, а без попыток заказ ожидает оплату.
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

    update udovenchuk_food."order"
    set pay_status = calculated_pay_status
    where order_id = checked_order_id;
end;
$$ language plpgsql;

-- NEW содержит новую строку, OLD содержит предыдущую.
create function udovenchuk_food.check_changed_order()
returns trigger as $$
declare
    attached_product_id uuid;
begin
    if tg_op = 'DELETE' then
        perform udovenchuk_food.check_order_integrity(old.order_id);
    else
        if tg_table_name = 'order_structure' then
            attached_product_id := new.product_id;
        end if;

        perform udovenchuk_food.check_order_integrity(new.order_id, attached_product_id);

        if tg_op = 'UPDATE' then
            if old.order_id <> new.order_id then
                perform udovenchuk_food.check_order_integrity(old.order_id);
            end if;
        end if;
    end if;

    return null;
end;
$$ language plpgsql;

-- При смене ресторана блюда проверяются заказы с этим блюдом.
create function udovenchuk_food.check_orders_with_changed_product()
returns trigger as $$
begin
    perform udovenchuk_food.check_order_integrity(os.order_id)
    from udovenchuk_food.order_structure os
    where os.product_id = new.product_id
    order by os.order_id;

    return null;
end;
$$ language plpgsql;

-- DEFERRABLE INITIALLY DEFERRED переносит проверки на COMMIT.
create constraint trigger order_check_after_insert
after insert on udovenchuk_food."order"
deferrable initially deferred
for each row execute function udovenchuk_food.check_changed_order();

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
)
execute function udovenchuk_food.check_changed_order();

create constraint trigger order_structure_check_order
after insert or update or delete on udovenchuk_food.order_structure
deferrable initially deferred
for each row execute function udovenchuk_food.check_changed_order();

create constraint trigger payment_check_order
after insert or update or delete on udovenchuk_food.payment
deferrable initially deferred
for each row execute function udovenchuk_food.check_changed_order();

create constraint trigger review_check_order
after insert or update or delete on udovenchuk_food.review
deferrable initially deferred
for each row execute function udovenchuk_food.check_changed_order();

create constraint trigger product_check_orders_after_restaurant_update
after update on udovenchuk_food.product
deferrable initially deferred
for each row
when (old.restaurant_id <> new.restaurant_id)
execute function udovenchuk_food.check_orders_with_changed_product();

-- Проверить и уже сохранённые заказы, если они есть.
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

-- Ожидается шесть строк с именами созданных триггеров.
select distinct event_object_table as table_name, trigger_name
from information_schema.triggers
where trigger_schema = 'udovenchuk_food'
  and trigger_name in (
      'order_check_after_insert',
      'order_check_after_update',
      'order_structure_check_order',
      'payment_check_order',
      'review_check_order',
      'product_check_orders_after_restaurant_update'
  )
order by table_name, trigger_name;
