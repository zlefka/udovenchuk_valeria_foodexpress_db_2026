-- FOOD-106. Продажи и лидеры по каждому ресторану.

create or replace function udovenchuk_food.get_statistic()
returns table (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
language sql
as $$
    -- Доставленные заказы используются в трёх расчётах.
    with delivered_orders as materialized (
        select o.order_id, o.restaurant_id, o.client_id, o.total_amount
        from udovenchuk_food."order" o
        where o.status = 'доставлен'
    ),
    restaurant_totals as (
        select o.restaurant_id, sum(o.total_amount) as total_amount,
               avg(o.total_amount) as avg_amount
        from delivered_orders o
        group by o.restaurant_id
    ),
    product_totals as (
        select o.restaurant_id, s.product_id, sum(s.quantity) as quantity_sold
        from delivered_orders o
        join udovenchuk_food.order_structure s on s.order_id = o.order_id
        group by o.restaurant_id, s.product_id
    ),
    best_products as (
        select distinct on (p.restaurant_id) p.restaurant_id, p.product_id
        from product_totals p
        order by p.restaurant_id, p.quantity_sold desc, random()
    ),
    client_totals as (
        select o.restaurant_id, o.client_id, count(*) as order_count
        from delivered_orders o
        group by o.restaurant_id, o.client_id
    ),
    best_clients as (
        select distinct on (c.restaurant_id) c.restaurant_id, c.client_id
        from client_totals c
        order by c.restaurant_id, c.order_count desc, random()
    )
    select r.restaurant_name, p.product_name, t.total_amount, t.avg_amount, c.login
    from udovenchuk_food.restaurant r
    left join restaurant_totals t on t.restaurant_id = r.restaurant_id
    left join best_products bp on bp.restaurant_id = r.restaurant_id
    left join udovenchuk_food.product p on p.product_id = bp.product_id
    left join best_clients bc on bc.restaurant_id = r.restaurant_id
    left join udovenchuk_food.client c on c.client_id = bc.client_id
    order by r.restaurant_name, r.restaurant_id
$$;
