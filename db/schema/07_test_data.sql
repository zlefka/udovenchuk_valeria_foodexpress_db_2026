-- Каждый вызов добавляет новые данные. Выплаты создаются за текущий и пять предыдущих месяцев.

create or replace procedure udovenchuk_food.insert_test_data(value integer)
as $$
declare
    restaurant_statuses udovenchuk_food.restaurant_status[] := enum_range(null::udovenchuk_food.restaurant_status);
    product_statuses udovenchuk_food.product_status[] := enum_range(null::udovenchuk_food.product_status);
    courier_statuses udovenchuk_food.courier_status[] := enum_range(null::udovenchuk_food.courier_status);
    order_statuses udovenchuk_food.order_status[] := enum_range(null::udovenchuk_food.order_status);
    payment_types udovenchuk_food.payment_type[] := enum_range(null::udovenchuk_food.payment_type);
    payment_statuses udovenchuk_food.payment_status[] := enum_range(null::udovenchuk_food.payment_status);
    review_types udovenchuk_food.review_entity_type[] := enum_range(null::udovenchuk_food.review_entity_type);

    new_client_id uuid;
    new_courier_id uuid;
    new_category_id uuid;
    new_restaurant_id uuid;
    new_product_id uuid;
    new_address_id uuid;
    new_order_id uuid;
    new_order_total numeric(14, 2);
    client_addresses uuid[] := array[]::uuid[];
    street_name varchar(200);
    product_price numeric(14, 2);
    item_quantity integer;
    review_type udovenchuk_food.review_entity_type;
    reviewed_id uuid;

    current_month timestamp := date_trunc('month', localtimestamp);
    order_month_offsets integer[] := array[5, 4, 2, 1, 0];
    ordered_at timestamp;
    delivered_at timestamp;
    pay_month timestamp;
    applied_coefficient numeric(3, 2);
    delivered_count bigint;
    monthly_commission numeric;
begin
    if value is null or value < 0 then
        raise exception 'Количество групп данных должно быть целым числом от 0';
    end if;

    -- Одна группа содержит клиента, курьера, категорию и ресторан.
    for group_number in 1..value loop
        loop
            new_client_id := exts.uuid_generate_v4();
            insert into udovenchuk_food.client (client_id, login, password, phone_number)
            values (
                new_client_id,
                'client_' || new_client_id::text,
                md5(random()::text),
                '+79' || (100000000 + floor(random() * 900000000)::int)::text
            )
            on conflict do nothing;
            exit when found;
        end loop;

        insert into udovenchuk_food.courier (fio, phone_number, status, hire_date)
        values (
            'Курьер ' || group_number,
            '+79' || (100000000 + floor(random() * 900000000)::int)::text,
            courier_statuses[1],
            (current_month - interval '5 months')::date
        )
        returning courier_id into new_courier_id;

        insert into udovenchuk_food.product_category (product_category_name)
        values ('Категория ' || group_number)
        returning product_category_id into new_category_id;

        -- На каждой учебной улице один адрес ресторана и четыре адреса клиента.
        street_name := 'Учебная ' || new_client_id::text;
        insert into udovenchuk_food.address (street, house_number)
        values (street_name, '1')
        returning address_id into new_address_id;

        insert into udovenchuk_food.restaurant (
            restaurant_name, address_id, description, work_start, work_end, company_details, status
        )
        values (
            'Ресторан ' || group_number, new_address_id, 'Учебный ресторан',
            '09:00', '22:00', 'Тестовые реквизиты', restaurant_statuses[1]
        )
        returning restaurant_id into new_restaurant_id;

        for address_number in 1..4 loop
            insert into udovenchuk_food.address (street, house_number)
            values (street_name, (address_number + 1)::text)
            returning address_id into new_address_id;

            client_addresses[address_number] := new_address_id;

            insert into udovenchuk_food.client_address (client_id, address_id)
            values (new_client_id, new_address_id);
        end loop;

        -- Пять блюд, пять заказов, по одной позиции, оплате и отзыву на заказ.
        for order_number in 1..5 loop
            product_price := 1000 + floor(random() * 1500);
            item_quantity := 1 + order_number % 3;

            insert into udovenchuk_food.product (
                product_name, product_category_id, restaurant_id, price, description, status
            )
            values (
                'Блюдо ' || order_number, new_category_id, new_restaurant_id,
                product_price, 'Учебное блюдо', product_statuses[1]
            )
            returning product_id into new_product_id;

            ordered_at := least(
                localtimestamp,
                current_month - order_month_offsets[order_number] * interval '1 month'
                    + interval '1 day 12 hours'
            );
            delivered_at := least(localtimestamp, ordered_at + interval '40 minutes');

            insert into udovenchuk_food."order" (
                client_id, restaurant_id, courier_id, address_id,
                order_timestamp, delivery_timestamp, order_amount, status, description
            )
            values (
                new_client_id, new_restaurant_id, new_courier_id,
                client_addresses[1 + (order_number - 1) % 4],
                ordered_at, delivered_at, product_price * item_quantity,
                order_statuses[4], 'Учебный заказ'
            )
            returning order_id, total_amount into new_order_id, new_order_total;

            insert into udovenchuk_food.order_structure (order_id, product_id, quantity)
            values (new_order_id, new_product_id, item_quantity);

            insert into udovenchuk_food.payment (
                order_id, payment_type, amount, transaction_reference, transaction_timestamp, status
            )
            values (
                new_order_id, payment_types[1 + (order_number - 1) % 3], new_order_total,
                'test_' || new_order_id::text,
                least(delivered_at, ordered_at + interval '5 minutes'), payment_statuses[1]
            );

            review_type := review_types[1 + (order_number - 1) % 3];
            if review_type = 'блюдо' then
                reviewed_id := new_product_id;
            elsif review_type = 'ресторан' then
                reviewed_id := new_restaurant_id;
            else
                reviewed_id := new_order_id;
            end if;

            insert into udovenchuk_food.review (
                client_id, order_id, entity_type, entity_id, description, rating, review_timestamp
            )
            values (
                new_client_id, new_order_id, review_type, reviewed_id,
                'Учебный отзыв', 3 + order_number % 3,
                least(localtimestamp, delivered_at + interval '20 minutes')
            );
        end loop;

        -- Среднее вычисляется по отзывам. AVG возвращает NULL, когда отзывов нет.
        update udovenchuk_food.product p
        set rating = (
            select round(avg(r.rating), 2)
            from udovenchuk_food.review r
            where r.entity_type = 'блюдо' and r.entity_id = p.product_id
        )
        where p.restaurant_id = new_restaurant_id;

        update udovenchuk_food.restaurant
        set rating = (
            select round(avg(r.rating), 2)
            from udovenchuk_food.review r
            where r.entity_type = 'ресторан' and r.entity_id = new_restaurant_id
        )
        where restaurant_id = new_restaurant_id;

        -- Коэффициент в начале периода равен 0.10. Дальше переносим его из месяца в месяц.
        applied_coefficient := 0.10;
        for month_number in reverse 5..0 loop
            pay_month := current_month - month_number * interval '1 month';

            select count(*), coalesce(sum(o.commission), 0)
            into delivered_count, monthly_commission
            from udovenchuk_food."order" o
            where o.courier_id = new_courier_id
              and o.status = 'доставлен'
              and o.order_timestamp >= pay_month
              and o.order_timestamp < pay_month + interval '1 month';

            insert into udovenchuk_food.courier_pay (year, month, courier_id, amount, coefficient_used)
            values (
                extract(year from pay_month)::int, extract(month from pay_month)::int,
                new_courier_id, round(monthly_commission * applied_coefficient, 2), applied_coefficient
            );

            if delivered_count <= 150 then
                applied_coefficient := 0.10;
            elsif delivered_count <= 250 then
                applied_coefficient := 0.20;
            elsif delivered_count <= 500 then
                applied_coefficient := 0.30;
            else
                applied_coefficient := 0.50;
            end if;
        end loop;

        update udovenchuk_food.courier
        set coefficient = applied_coefficient
        where courier_id = new_courier_id;
    end loop;
end;
$$ language plpgsql;
