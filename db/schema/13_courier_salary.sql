-- FOOD-107. Выплаты за текущий месяц и коэффициенты на следующий.

create or replace procedure udovenchuk_food.courier_salary()
language plpgsql
as $$
declare
    month_start timestamp := date_trunc('month', current_date::timestamp);
    next_month_start timestamp := month_start + interval '1 month';
    pay_year integer := extract(year from month_start)::integer;
    pay_month integer := extract(month from month_start)::integer;
    courier_row record;
    delivery_count bigint;
    commission_sum numeric;
    next_coefficient numeric(3, 2);
begin
    -- Параллельные запуски рассчитывают выплаты курьерам по очереди.
    for courier_row in
        select c.courier_id, c.status, c.coefficient
        from udovenchuk_food.courier c
        order by c.courier_id
        for no key update
    loop
        select count(*), coalesce(sum(o.commission), 0)
        into delivery_count, commission_sum
        from udovenchuk_food."order" o
        where o.courier_id = courier_row.courier_id
          and o.status = 'доставлен'
          and o.order_timestamp >= month_start
          and o.order_timestamp < next_month_start;

        -- При повторном расчёте используем ставку из уже записанной выплаты.
        insert into udovenchuk_food.courier_pay as saved_pay
            (year, month, courier_id, amount, coefficient_used)
        values (
            pay_year, pay_month, courier_row.courier_id,
            round(commission_sum * courier_row.coefficient, 2), courier_row.coefficient
        )
        on conflict (year, month, courier_id) do update
        set amount = round(commission_sum * saved_pay.coefficient_used, 2);

        if courier_row.status <> 'уволен' then
            next_coefficient := case
                when delivery_count <= 150 then 0.10
                when delivery_count <= 250 then 0.20
                when delivery_count <= 500 then 0.30
                else 0.50
            end;

            update udovenchuk_food.courier
            set coefficient = next_coefficient
            where courier_id = courier_row.courier_id;
        end if;
    end loop;
end;
$$;
