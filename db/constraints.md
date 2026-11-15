# Обоснование ограничений

Скрипты `01_schema.sql`–`06_integrity.sql` создают схему `udovenchuk_food` с 12 таблицами из ERD и 8 enum-типами. Скрипт `08_order_checks.sql` дополняет проверки заказов для FOOD-101.

Все поля с идентификаторами имеют тип `uuid`. Для самостоятельных первичных ключей используется `exts.uuid_generate_v4()` из заранее подготовленной схемы `exts` (BR-11.1, BR-13.3). Ограничение `UNIQUE NULLS NOT DISTINCT` для адресов требует PostgreSQL 15 или новее. Имя `"order"` заключено в двойные кавычки по BR-13.1.

## Enum-типы

Значения статусов и типов заданы через `CREATE TYPE ... AS ENUM` по BR-11.5.

| Тип | Значения | BR |
| --- | --- | --- |
| `restaurant_status` | `'активен'`, `'неактивен'` | BR-4.3 |
| `product_status` | `'доступно'`, `'нет_в_наличии'`, `'архив'` | BR-5.5 |
| `courier_status` | `'свободен'`, `'занят'`, `'на_доставке'`, `'уволен'` | BR-6.2 |
| `order_status` | `'создан'`, `'готовится'`, `'в_доставке'`, `'доставлен'`, `'отменён'` | BR-7.7 |
| `order_pay_status` | `'ожидает'`, `'оплачен'`, `'ошибка'` | BR-7.9 |
| `payment_status` | `'успех'`, `'ошибка'`, `'в_обработке'` | BR-8.2 |
| `payment_type` | `'карта'`, `'наличные'`, `'безнал'` | BR-8.2 |
| `review_entity_type` | `'блюдо'`, `'ресторан'`, `'заказ'` | BR-9.1 |

## Ловушки

### Ловушка 1: `payment` — неполная сущность

В `payment` добавлены `payment_type` для способа оплаты, `amount` для суммы попытки, `transaction_reference` для внешнего идентификатора транзакции, `transaction_timestamp` для её времени и `status` для результата (BR-8.2, BR-8.3). Поле `order_id` связывает попытку с заказом. Для связи с платёжным провайдером достаточно его идентификатора операции (BR-8.5).

Способ оплаты хранится в `payment`, поскольку у одного заказа могут быть попытки с разными способами, например картой и наличными (BR-8.6).

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

Составной внешний ключ `order_client_address_fk` связывает `"order"(client_id, address_id)` с `client_address(client_id, address_id)`. В заказе можно указать только ту пару клиента и адреса, которая уже существует в таблице привязок.

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

Функция `check_order_integrity` берёт ресторан заказа и сравнивает его с рестораном каждого блюда из `order_structure`. При несовпадении PostgreSQL отклоняет транзакцию. Триггеры запускают проверку при изменении позиции, ресторана заказа или ресторана блюда.

### Ловушка 4: `review` — полиморфизм (BR-9.1)

Поле `entity_type` задаёт, что обозначает `entity_id`. Обычный внешний ключ может ссылаться на одну таблицу, а в этой модели таблица зависит от типа объекта. Функция `check_order_integrity` проверяет, что:

- для типа «заказ» `entity_id` совпадает с `order_id` этого отзыва;
- для типа «ресторан» `entity_id` совпадает с рестораном заказа;
- для типа «блюдо» `entity_id` есть среди блюд в позициях заказа.

Отдельные внешние ключи связывают отзыв с заказом и автором. Триггер сверяет, что автор отзыва является клиентом этого заказа (BR-9.2).

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
| --- | --- | --- | --- | --- |
| `client` | `login` | `client_login_not_blank` — `CHECK (btrim(login) <> '')` | BR-2.1, BR-11.3, BR-11.4 | Логин должен содержать значение после удаления пробелов по краям. |
| `client` | `phone_number` | `client_phone_not_blank` — `CHECK (btrim(phone_number) <> '')` | BR-2.1, BR-11.3, BR-11.4 | Номер телефона должен содержать значение после удаления пробелов по краям. |
| `client` | `password` | `client_password_md5` — `CHECK (password ~ '^[0-9a-f]{32}$')` | BR-2.3 | Формат MD5 проверяется по 32 шестнадцатеричным символам нижнего регистра. |
| `address` | `street` | `address_street_not_blank` — `CHECK (btrim(street) <> '')` | BR-3.1, BR-11.3 | Улица является обязательной частью адреса. |
| `address` | `house_number` | `address_house_not_blank` — `CHECK (btrim(house_number) <> '')` | BR-3.1, BR-11.3 | Номер дома является обязательной частью адреса. |
| `address` | `apartment_office` | `address_apartment_not_blank` — `CHECK (apartment_office is null or btrim(apartment_office) <> '')` | BR-3.2 | Если квартира или офис указаны, в строке должно быть значение после удаления пробелов по краям. |
| `restaurant` | `restaurant_name` | `restaurant_name_not_blank` — `CHECK (btrim(restaurant_name) <> '')` | BR-4.1, BR-11.3 | Ресторан должен иметь заполненное название. |
| `restaurant` | `work_start`, `work_end` | `restaurant_work_hours` — `CHECK (work_end > work_start)` | BR-4.4 | Ресторан закрывается позже времени открытия. |
| `restaurant` | `rating` | `restaurant_rating_range` — `CHECK (rating between 0 and 5)` | BR-4.2 | Рейтинг ресторана лежит в диапазоне от 0 до 5. |
| `product_category` | `product_category_name` | `product_category_name_not_blank` — `CHECK (btrim(product_category_name) <> '')` | BR-5.7, BR-11.3 | У каждой категории есть заполненное название. |
| `product` | `product_name` | `product_name_not_blank` — `CHECK (btrim(product_name) <> '')` | BR-5.2, BR-11.3 | У каждого блюда есть заполненное название. |
| `product` | `price` | `product_price_range` — `CHECK (price >= 0 and price <> 'NaN'::numeric)` | BR-5.3 | Цена блюда является неотрицательным числом. |
| `product` | `rating` | `product_rating_range` — `CHECK (rating between 0 and 5)` | BR-5.4 | Рейтинг блюда лежит в диапазоне от 0 до 5. |
| `courier` | `fio` | `courier_fio_not_blank` — `CHECK (btrim(fio) <> '')` | BR-6.1, BR-11.3 | ФИО используется для идентификации курьера в сведениях о сотрудниках. |
| `courier` | `phone_number` | `courier_phone_not_blank` — `CHECK (btrim(phone_number) <> '')` | BR-6.1, BR-11.3 | Телефон курьера должен быть заполнен. |
| `courier` | `status`, `dismissal_date` | `courier_dismissal_required` — `CHECK (status <> 'уволен' or dismissal_date is not null)` | BR-6.3 | Для статуса «уволен» требуется дата увольнения. |
| `courier` | `hire_date`, `dismissal_date` | `courier_employment_dates` — `CHECK (dismissal_date >= hire_date)` | BR-6.3 | Дата увольнения совпадает с датой найма или следует за ней. |
| `courier` | `coefficient` | `courier_coefficient_range` — `CHECK (coefficient between 0.10 and 0.50)` | BR-6.4 | Текущий коэффициент находится в пределах от 0,10 до 0,50. |
| `courier_pay` | `year` | `courier_pay_year_range` — `CHECK (year between 1 and 9999)` | BR-10.1, BR-10.3, BR-11.6 | Для периода выплаты выбран диапазон годов, который помещается в формат YYYY-MM. |
| `courier_pay` | `month` | `courier_pay_month_range` — `CHECK (month between 1 and 12)` | BR-10.1, BR-10.3 | В году двенадцать месяцев, номер месяца хранится числом. |
| `courier_pay` | `amount` | `courier_pay_amount_range` — `CHECK (amount >= 0 and amount <> 'NaN'::numeric)` | BR-10.4 | Выплата является неотрицательным числом. Нулевая выплата допустима. |
| `courier_pay` | `coefficient_used` | `courier_pay_coefficient_range` — `CHECK (coefficient_used between 0.10 and 0.50)` | BR-6.4, BR-10.2 | Коэффициент, применённый в месяце выплаты, имеет тот же допустимый диапазон, что и текущий. |
| `"order"` | `order_amount` | `order_amount_range` — `CHECK (order_amount >= 0 and order_amount <> 'NaN'::numeric)` | BR-5.3, BR-7.10 | Сумма без комиссии складывается из неотрицательных стоимостей блюд. |
| `"order"` | `total_amount` | `order_total_minimum` — `CHECK (total_amount >= 1000)` | BR-1.8, BR-7.11 | Сумма заказа с комиссией составляет минимум 1000 ₽. |
| `"order"` | `status`, `delivery_timestamp` | `order_delivery_required` — `CHECK ((status = 'доставлен') = (delivery_timestamp is not null))` | BR-7.12 | Время завершения доставки заполняется вместе со статусом «доставлен». |
| `"order"` | `order_timestamp`, `delivery_timestamp` | `order_delivery_dates` — `CHECK (delivery_timestamp >= order_timestamp)` | BR-7.13 | Доставка завершается в момент создания заказа или позже. |
| `order_structure` | `quantity` | `order_structure_quantity_positive` — `CHECK (quantity > 0 and quantity <> 'NaN'::numeric)` | BR-7.15 | Количество блюда положительное. Тип numeric(12, 3) допускает дробные значения. |
| `order_structure` | `unit_price` | `order_structure_unit_price_range` — `CHECK (unit_price >= 0 and unit_price <> 'NaN'::numeric)` | BR-5.3, BR-7.10 | Цена единицы блюда на момент заказа является неотрицательным числом. |
| `payment` | `transaction_reference` | `payment_transaction_reference_not_blank` — `CHECK (btrim(transaction_reference) <> '')` | BR-8.2, BR-8.3 | Для каждой попытки нужен заполненный идентификатор внешней транзакции. |
| `payment` | `amount` | `payment_amount_range` — `CHECK (amount >= 0 and amount <> 'NaN'::numeric)` | BR-7.11, BR-8.4 | Проверка отклоняет отрицательную или неопределённую сумму до сверки с итогом заказа. |
| `review` | `rating` | `review_rating_range` — `CHECK (rating between 1 and 5)` | BR-9.4 | Оценка в отзыве находится в диапазоне от 1 до 5. |

Проверки с `btrim` отклоняют пустые строки и строки из обычных пробелов. Проверки цены, стоимости блюд в заказе, суммы оплаты, выплаты и количества исключают специальное значение `NaN`, которое PostgreSQL допускает в типе `numeric`.

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
| --- | --- | --- | --- |
| `client` | `login` | BR-2.2 | `client_login_unique`. Каждый логин принадлежит одному клиенту. |
| `client` | `phone_number` | BR-2.2 | `client_phone_unique`. Каждый номер телефона принадлежит одному клиенту. |
| `address` | `street`, `house_number`, `apartment_office` с `NULLS NOT DISTINCT` | BR-3.1, BR-3.2, BR-3.3, BR-3.4 | `address_location_unique`. Физический адрес с одинаковыми улицей, домом и квартирой хранится в одной записи. NULLS NOT DISTINCT распространяет это правило на адреса без квартиры. |
| `restaurant` | `address_id` | BR-3.3, BR-3.4 | `restaurant_address_unique`. На одном физическом адресе может быть только один ресторан. |
| `payment` | `transaction_reference` | BR-8.3 | `payment_transaction_reference_unique`. Идентификатор транзакции платёжного провайдера уникален. |
| `review` | `order_id`, `entity_type`, `entity_id` | BR-9.1, BR-9.2, BR-9.5 | `review_order_entity_unique`. В рамках заказа объект может получить один отзыв. Тип входит в ключ, чтобы различать блюда, рестораны и заказы. |
| `payment` | `order_id` при `WHERE status = 'успех'` | BR-8.1, BR-8.7 | `payment_one_success_idx` допускает одну успешную попытку на заказ. Для доставленного заказа наличие успеха проверяет триггер. |

### Составные первичные ключи

| Таблица | Ключ | BR | Обоснование |
| --- | --- | --- | --- |
| `client_address` | `client_address_pk` (`client_id`, `address_id`) | BR-2.4, BR-2.5 | Пара клиента и адреса уникальна. Адрес может использоваться разными клиентами. |
| `courier_pay` | `courier_pay_pk` (`year`, `month`, `courier_id`) | BR-10.1, BR-10.3 | Для каждого курьера за один месяц хранится одна запись о выплате. |
| `order_structure` | `order_structure_pk` (`order_id`, `product_id`) | BR-7.14, BR-7.16 | Одно блюдо занимает одну позицию заказа. Несколько порций задаются количеством. |

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
| --- | --- | --- | --- | --- |
| `client_address` | `client_id` | `client` (`client_id`) | BR-2.4 | `client_address_client_fk`. Связь с адресом относится к существующему клиенту. |
| `client_address` | `address_id` | `address` (`address_id`) | BR-2.4, BR-3.1 | `client_address_address_fk`. Связь клиента указывает на существующий адрес. |
| `restaurant` | `address_id` | `address` (`address_id`) | BR-3.3 | `restaurant_address_fk`. Ресторан использует адрес из таблицы address. |
| `product` | `product_category_id` | `product_category` (`product_category_id`) | BR-5.1, BR-5.7 | `product_category_fk`. У блюда одна существующая категория. |
| `product` | `restaurant_id` | `restaurant` (`restaurant_id`) | BR-5.1 | `product_restaurant_fk`. У блюда один существующий ресторан. |
| `courier_pay` | `courier_id` | `courier` (`courier_id`) | BR-10.2, BR-10.3 | `courier_pay_courier_fk`. Выплата относится к существующему курьеру. |
| `"order"` | `client_id` | `client` (`client_id`) | BR-7.1, BR-7.2 | `order_client_fk`. Заказ оформляет существующий клиент. |
| `"order"` | `restaurant_id` | `restaurant` (`restaurant_id`) | BR-7.2 | `order_restaurant_fk`. Заказ оформлен в одном существующем ресторане. |
| `"order"` | `courier_id` | `courier` (`courier_id`) | BR-7.5 | `order_courier_fk`. За доставку отвечает существующий курьер. |
| `"order"` | `address_id` | `address` (`address_id`) | BR-7.4 | `order_address_fk`. Адрес доставки существует в справочнике адресов. |
| `"order"` | `client_id`, `address_id` | `client_address` (`client_id`, `address_id`) | BR-7.4 | `order_client_address_fk`. Клиент и адрес доставки связаны друг с другом в client_address. |
| `order_structure` | `order_id` | `"order"` (`order_id`) | BR-7.14 | `order_structure_order_fk`. Позиция относится к существующему заказу. |
| `order_structure` | `product_id` | `product` (`product_id`) | BR-7.14 | `order_structure_product_fk`. Позиция ссылается на существующее блюдо. |
| `payment` | `order_id` | `"order"` (`order_id`) | BR-8.1 | `payment_order_fk`. Каждая попытка оплаты относится к своему заказу. |
| `review` | `client_id` | `client` (`client_id`) | BR-9.2 | `review_client_fk`. Автор отзыва существует как клиент. |
| `review` | `order_id` | `"order"` (`order_id`) | BR-9.2 | `review_order_fk`. У каждого отзыва есть заказ, по которому его оставили. |

По умолчанию внешние ключи используют `NO ACTION`. Адрес хранится отдельной записью и сохраняется после удаления ресторана или привязки клиента (BR-3.5).

## NOT NULL (только бизнес-обязательные)

| Таблица | Столбец | BR | Обоснование |
| --- | --- | --- | --- |
| `client` | `login`, `password`, `phone_number` | BR-2.1, BR-11.3 | Все три значения используются при регистрации клиента. |
| `restaurant` | `company_details`, `work_start`, `work_end` | BR-4.1, BR-4.4, BR-4.5 | Для ресторана нужны реквизиты и обе границы рабочего времени. |
| `courier` | `hire_date`, `coefficient` | BR-6.1, BR-6.4, BR-10.2 | Дата найма задаёт начало работы, текущий коэффициент нужен для расчёта выплаты. |
| `courier_pay` | `amount`, `coefficient_used` | BR-10.2, BR-10.4 | В месячной записи фиксируются сумма и применённый коэффициент. Выплата за месяц без доставок имеет значение 0. |
| `"order"` | `order_timestamp`, `order_amount`, `pay_status` | BR-7.1, BR-7.8, BR-7.10, BR-7.12 | Время создания, стоимость блюд и состояние оплаты нужны с момента оформления. |
| `order_structure` | `quantity` | BR-7.14, BR-7.15 | Позиции всегда соответствует конкретное количество блюда. |
| `order_structure` | `unit_price` | BR-7.10 | Цена единицы нужна для расчёта стоимости позиции по цене на момент заказа. |
| `payment` | `payment_type`, `amount`, `transaction_reference`, `transaction_timestamp`, `status` | BR-8.2, BR-8.3 | Каждая попытка оплаты содержит сведения об операции и её результате. |
| `review` | `entity_type`, `entity_id`, `rating` | BR-9.1, BR-9.3, BR-9.4 | У отзыва должен быть конкретный объект и выставленная оценка. |

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
| --- | --- | --- | --- |
| `address` | `apartment_office` | BR-3.2 | Квартира или офис могут отсутствовать, например у частного дома. |
| `restaurant` | `rating` | BR-9.7 | До первого отзыва о ресторане среднего рейтинга нет. |
| `product` | `photo_url` | BR-5.6 | Фотография блюда необязательна. Если её добавили, хранится ссылка. |
| `product` | `rating` | BR-9.7 | До первого отзыва о блюде среднего рейтинга нет. |
| `courier` | `dismissal_date` | BR-6.3 | У работающего курьера дата увольнения может отсутствовать. |
| `"order"` | `delivery_timestamp` | BR-7.12 | Время окончания доставки может отсутствовать до перехода в статус «доставлен». |
| `review` | `photo_url` | BR-9.3 | К отзыву можно приложить фотографию по желанию. |

## DEFAULT и GENERATED

`DEFAULT exts.uuid_generate_v4()` установлен у `client.client_id`, `address.address_id`, `restaurant.restaurant_id`, `product_category.product_category_id`, `product.product_id`, `courier.courier_id`, `"order".order_id`, `payment.payment_id`, `review.review_id`. При вставке идентификатор создаёт PostgreSQL (BR-11.1, BR-13.3).

| Таблица | Столбец | Что | Обоснование |
| --- | --- | --- | --- |
| `courier` | `coefficient` | `DEFAULT 0.10` | Коэффициент нового курьера равен 0,10. (BR-6.5) |
| `"order"` | `order_timestamp` | `DEFAULT localtimestamp` | Время создания берётся из текущей транзакции по умолчанию. (BR-7.1, BR-7.12, BR-11.2) |
| `"order"` | `pay_status` | `DEFAULT 'ожидает'` | Новый заказ ожидает оплату. Далее статус вычисляется по попыткам. (BR-7.8, BR-7.9, BR-8.7) |
| `payment` | `transaction_timestamp` | `DEFAULT localtimestamp` | По умолчанию записывается время текущей транзакции. Время от провайдера можно передать явно. (BR-8.2, BR-11.2) |
| `review` | `review_timestamp` | `DEFAULT localtimestamp` | По умолчанию записывается дата и время создания отзыва. (BR-9.3, BR-11.2) |
| `"order"` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | Комиссия равна 10% стоимости блюд с округлением до копеек. (BR-1.4, BR-7.10) |
| `"order"` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | Итог складывается из стоимости блюд и округлённой комиссии. (BR-1.5, BR-7.10) |

Суммы хранятся в `numeric(14, 2)`, чтобы сохранить точность до копеек. Для количества используется `numeric(12, 3)`, для рейтингов и коэффициентов — `numeric(3, 2)`. Телефоны и номера домов хранятся строками, чтобы сохранить символы вроде `+` в телефоне и `А` в номере дома (BR-11.6).

## Проверки связанных данных

Функция `check_order_integrity` проверяет наличие хотя бы одной позиции (BR-7.14), равенство `order_amount` округлённой сумме `quantity * unit_price` по позициям (BR-7.10) и равенство суммы каждой попытки оплаты итогу заказа (BR-8.4). Успешная попытка даёт статус «оплачен». При наличии только ошибок выставляется «ошибка». Без попыток или при наличии попытки в обработке до успеха заказ ожидает оплату (BR-8.7). При переходе в статус «доставлен» должна существовать ровно одна успешная попытка (BR-8.1). Такой порядок позволяет сохранить заказ, который ещё ожидает оплату.

| Триггер | Когда проверяется заказ |
|---|---|
| `order_check_after_insert`, `order_check_after_update` | При создании заказа или изменении его идентификатора, клиента, ресторана, стоимости блюд, статуса заказа либо статуса оплаты. |
| `order_structure_check_order` | При добавлении, изменении или удалении позиции. |
| `payment_check_order` | При добавлении, изменении или удалении попытки оплаты. |
| `review_check_order` | При добавлении, изменении или удалении отзыва. |
| `product_check_orders_after_restaurant_update` | При смене ресторана блюда проверяются заказы с этим блюдом. |
| `order_structure_fill_unit_price` | Перед вставкой позиции берёт цену из меню, если цена позиции не указана. |
| `review_rating_change` | После вставки, изменения или удаления отзыва пересчитывает среднее для затронутых блюд и ресторанов (BR-9.6, BR-9.7). |

Проверки заказа из `06_integrity.sql` и `08_order_checks.sql` по умолчанию выполняются при `COMMIT`. Это позволяет вставить заказ, его позиции и оплату отдельными командами внутри одной транзакции. При переносе позиции, оплаты или отзыва проверяются старый и новый заказы. Для ранее записанных тестовых позиций цена берётся из текущего меню и сверяется с уже сохранённой суммой заказа при установке.

## Нормализация (3НФ)

Данные клиента, адреса, ресторана, курьера и категории хранятся в отдельных таблицах. Другие таблицы связываются с ними через идентификаторы. Составные ключи отражают смысл записей: `client_address` связывает пару клиента и адреса, количество в `order_structure` относится к паре заказа и блюда, а выплата в `courier_pay` относится к конкретному курьеру за год и месяц. `entity_type` и `entity_id` в отзыве вместе определяют объект. Его принадлежность заказу проверяется триггером.

В модели есть хранимые поля, значения которых следуют из других данных.

| Поля | Зависимость и способ поддержания |
|---|---|
| `"order".commission`, `"order".total_amount` | Вычисляются из `order_amount`. PostgreSQL пересчитывает их автоматически при изменении исходной суммы (BR-7.10). |
| `order_structure.unit_price` | Историческая цена относится к конкретной паре заказа и блюда. Она используется при сверке `order_amount` с позициями (BR-7.10). |
| `review.client_id` | Клиент определяется по `order_id`. Поле автора предусмотрено ERD. Триггер сверяет его с клиентом заказа (BR-9.2). |
| `payment.amount` | Каждая попытка хранит сумму операции по BR-8.2. По BR-8.4 она равна `total_amount` заказа, поэтому проверяется триггером. |
| `"order".pay_status` | Сводное состояние хранится в заказе по BR-7.8 и рассчитывается по строкам `payment` (BR-8.7). |
| `product.rating`, `restaurant.rating` | Хранимые средние оценки ускоряют чтение меню и ресторанов. В `11_rating_change.sql` функция `rating_change()` пересчитывает среднее после добавления, изменения или удаления отзыва. При переносе отзыва пересчитываются оба объекта. Если отзывов нет, рейтинг равен `NULL` (BR-9.6, BR-9.7, FOOD-105). |

В `"order"`, `review` и `payment` есть отступления от строгой 3НФ из-за зависимостей от неключевых полей. Вычисляемые столбцы и проверки между таблицами поддерживают согласованность этих данных.

## Тестовые данные (FOOD-102)

Каждый вызов `insert_test_data(value)` добавляет `value` новых групп данных. Группа включает клиента, курьера, ресторан, категорию, пять адресов, пять блюд и пять заказов. Каждый заказ содержит позицию, одну успешную попытку оплаты и отзыв. Выплаты рассчитываются за текущий и пять предыдущих календарных месяцев по комиссиям доставленных заказов. Повторный вызов сохраняет ранее созданные группы.
