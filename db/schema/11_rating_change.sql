-- FOOD-105. Рейтинг блюда и ресторана после изменения отзыва.

begin;

create or replace function udovenchuk_food.recalculate_rating(
    target_type udovenchuk_food.review_entity_type,
    target_id uuid
)
returns void as $$
declare
    new_rating numeric(3, 2);
begin
    if target_type = 'заказ' then
        return;
    end if;

    -- Блокируем строку объекта, чтобы два отзыва не пересчитали рейтинг одновременно.
    if target_type = 'блюдо' then
        perform p.product_id
        from udovenchuk_food.product p
        where p.product_id = target_id
        for no key update;
    else
        perform r.restaurant_id
        from udovenchuk_food.restaurant r
        where r.restaurant_id = target_id
        for no key update;
    end if;

    -- AVG возвращает NULL, когда отзывов больше нет.
    select round(avg(r.rating), 2)
    into new_rating
    from udovenchuk_food.review r
    where r.entity_type = target_type and r.entity_id = target_id;

    if target_type = 'блюдо' then
        update udovenchuk_food.product
        set rating = new_rating
        where product_id = target_id;
    else
        update udovenchuk_food.restaurant
        set rating = new_rating
        where restaurant_id = target_id;
    end if;
end;
$$ language plpgsql;

create or replace function udovenchuk_food.rating_change()
returns trigger as $$
begin
    if tg_op = 'INSERT' then
        perform udovenchuk_food.recalculate_rating(new.entity_type, new.entity_id);
    elsif tg_op = 'DELETE' then
        perform udovenchuk_food.recalculate_rating(old.entity_type, old.entity_id);
    else
        -- Если отзыв перенесли, пересчитываем и прежний объект.
        if old.entity_type <> new.entity_type or old.entity_id <> new.entity_id then
            perform udovenchuk_food.recalculate_rating(old.entity_type, old.entity_id);
        end if;

        perform udovenchuk_food.recalculate_rating(new.entity_type, new.entity_id);
    end if;

    return null;
end;
$$ language plpgsql;

create or replace trigger review_rating_change
after insert or update or delete on udovenchuk_food.review
for each row execute function udovenchuk_food.rating_change();

-- Приводим рейтинги существующих блюд и ресторанов к среднему по отзывам.
update udovenchuk_food.product p
set rating = (
    select round(avg(r.rating), 2)
    from udovenchuk_food.review r
    where r.entity_type = 'блюдо' and r.entity_id = p.product_id
);

update udovenchuk_food.restaurant p
set rating = (
    select round(avg(r.rating), 2)
    from udovenchuk_food.review r
    where r.entity_type = 'ресторан' and r.entity_id = p.restaurant_id
);

commit;
