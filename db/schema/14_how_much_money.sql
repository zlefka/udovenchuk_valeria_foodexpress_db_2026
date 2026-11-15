-- FOOD-108. Доходы, выплаты и прибыль по месяцам.

create or replace view udovenchuk_food.how_much_money as
with recursive order_months as (
    select date_trunc('month', o.order_timestamp) as month_start,
           sum(o.order_amount) as sum_no_commission,
           sum(o.total_amount) as sum_with_commission
    from udovenchuk_food."order" o
    where o.status = 'доставлен'
    group by date_trunc('month', o.order_timestamp)
),
bounds as (
    select min(month_start) as first_month, max(month_start) as last_month
    from order_months
),
months (month_start, last_month) as (
    select first_month, last_month
    from bounds
    where first_month is not null

    union all

    select month_start + interval '1 month', last_month
    from months
    where month_start < last_month
),
pay_months as (
    select make_date(p.year, p.month, 1)::timestamp as month_start,
           sum(p.amount) as courier_pay
    from udovenchuk_food.courier_pay p
    group by p.year, p.month
),
monthly_amounts as (
    select m.month_start,
           coalesce(o.sum_no_commission, 0) as sum_no_commission,
           coalesce(o.sum_with_commission, 0) as sum_with_commission,
           coalesce(p.courier_pay, 0) as courier_pay
    from months m
    left join order_months o on o.month_start = m.month_start
    left join pay_months p on p.month_start = m.month_start
),
monthly_commissions as (
    select a.*, a.sum_with_commission - a.sum_no_commission as commission
    from monthly_amounts a
),
previous_commissions as (
    select c.*, lag(c.commission) over (order by c.month_start) as prev_commission
    from monthly_commissions c
)
select to_char(month_start, 'YYYY-MM') as year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission - prev_commission as commission_diff,
       courier_pay,
       commission - courier_pay as net_profit
from previous_commissions;
