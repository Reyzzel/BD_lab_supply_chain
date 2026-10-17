SET search_path TO scm, public;

-- Довідкові дані
BEGIN;

INSERT INTO app_user (username, password_hash, role) VALUES
    ('admin',         '$2a$11$demo.hash.admin',   'admin'),             -- 1
    ('olena.manager', '$2a$11$demo.hash.olena',   'manager'),           -- 2
    ('ivan.sales',    '$2a$11$demo.hash.ivan',    'sales'),             -- 3
    ('petro.store',   '$2a$11$demo.hash.petro',   'warehouse_worker');  -- 4

CALL sp_set_current_user(1);

-- Відділ створюється разом із керівником
CALL sp_department_create('Відділ продажів', '+380441110001', 'Коваленко Олена Петрівна',  'Керівник відділу продажів', 45000);   -- dept 1, emp 1
CALL sp_department_create('Відділ логістики', '+380441110002', 'Бондаренко Сергій Іванович', 'Керівник логістики',      42000);   -- dept 2, emp 2
CALL sp_department_create('Відділ закупівель','+380441110003', 'Ткаченко Марія Олегівна',   'Керівник закупівель',      43000);   -- dept 3, emp 3

CALL sp_employee_create('Мельник Іван Андрійович',   'Менеджер з продажу',     28000, 1, 1);   -- 4
CALL sp_employee_create('Шевчук Андрій Петрович',    'Стажер з продажу',       16000, 1, 4);   -- 5
CALL sp_employee_create('Бойко Петро Васильович',    'Комірник',               21000, 2, 2);   -- 6
CALL sp_employee_create('Кравець Наталія Сергіївна', 'Спеціаліст із закупівель',27000, 3, 3);  -- 7
CALL sp_employee_create('Лисенко Олег Миколайович',  'Стажер з логістики',     15000, 2, 6);   -- 8

UPDATE app_user SET employee_id = 1 WHERE id = 2;
UPDATE app_user SET employee_id = 4 WHERE id = 3;
UPDATE app_user SET employee_id = 6 WHERE id = 4;

CALL sp_customer_create('ТОВ "Рітейл Плюс"',   '+380671234567', 'orders@retailplus.ua', 'м. Київ, вул. Хрещатик, 10');   -- 1
CALL sp_customer_create('Гончаренко Ірина',    '+380501112233', 'irina.h@gmail.com',     'м. Одеса, вул. Дерибасівська, 5'); -- 2
CALL sp_customer_create('ФОП Савченко В. М.',  '+380931234567', NULL,                     'м. Львів, пл. Ринок, 1');           -- 3
CALL sp_customer_create('Романюк Дмитро',      NULL,            'd.romaniuk@ukr.net',     'м. Харків, просп. Науки, 14');      -- 4

CALL sp_product_create('EL-PHONE-001', 'Смартфон Nova X',        14999.00, 'electronics', 12);
CALL sp_product_create('EL-LAPT-002',  'Ноутбук ProBook 15',     32999.00, 'electronics', 24);
CALL sp_product_create('EL-HEAD-003',  'Навушники SoundPro',      2499.00, 'electronics', 6);
CALL sp_product_create('CL-JACK-001',  'Куртка зимова',           3899.00, 'clothing', NULL, 'L',  'Поліестер, пух');
CALL sp_product_create('CL-TSHT-002',  'Футболка базова',          499.00, 'clothing', NULL, 'M',  'Бавовна 100%');
CALL sp_product_create('CL-JEAN-003',  'Джинси класичні',         1599.00, 'clothing', NULL, '32', 'Денім');

INSERT INTO supplier (edrpou, company_name, phone, email) VALUES
    ('12345678', 'ТОВ "ТехноІмпорт"',   '+380442000001', 'sales@techimport.ua'),
    ('23456789', 'ПрАТ "Текстиль-Юг"',  '+380482000002', 'info@textile-ug.ua'),
    ('34567890', 'ТОВ "ГаджетОпт"',     '+380572000003', 'opt@gadget.ua');

INSERT INTO contract (contract_number, supplier_edrpou, sign_date, expiry_date) VALUES
    ('K-2026/001', '12345678', DATE '2026-01-10', DATE '2027-01-09'),
    ('K-2026/002', '23456789', DATE '2026-02-01', DATE '2026-12-31'),
    ('K-2025/017', '34567890', DATE '2025-03-01', DATE '2026-03-01');   -- уже завершився

INSERT INTO contract_item (contract_number, product_sku, agreed_price, max_quantity) VALUES
    ('K-2026/001', 'EL-PHONE-001', 11500.00, 200),
    ('K-2026/001', 'EL-LAPT-002',  26000.00, 50),
    ('K-2026/001', 'EL-HEAD-003',   1700.00, NULL),
    ('K-2026/002', 'CL-JACK-001',   2400.00, 300),
    ('K-2026/002', 'CL-TSHT-002',    210.00, 1000),
    ('K-2026/002', 'CL-JEAN-003',    900.00, 400),
    ('K-2025/017', 'EL-HEAD-003',   1650.00, 100);

INSERT INTO warehouse (name, address) VALUES
    ('Склад Київ-Північ', 'м. Київ, вул. Складська, 3'),     -- 1
    ('Склад Одеса-Порт',  'м. Одеса, Митна пл., 1');         -- 2

COMMIT;

-- Поставки (тригер поповнює залишки)
BEGIN;
CALL sp_set_current_user(4);   -- комірник

CALL sp_supply_register('K-2026/001', 'EL-PHONE-001', 1, DATE '2026-03-15', 60);    -- 1
CALL sp_supply_register('K-2026/001', 'EL-LAPT-002',  1, DATE '2026-03-15', 20);    -- 2
CALL sp_supply_register('K-2026/001', 'EL-HEAD-003',  2, DATE '2026-04-02', 150);   -- 3
CALL sp_supply_register('K-2026/002', 'CL-JACK-001',  2, DATE '2026-09-20', 80);    -- 4
CALL sp_supply_register('K-2026/002', 'CL-TSHT-002',  1, DATE '2026-09-25', 300);   -- 5
CALL sp_supply_register('K-2026/002', 'CL-JEAN-003',  1, DATE '2026-11-05', 100);   -- 6 (запланована)

CALL sp_supply_set_status(1, 'in_transit');
CALL sp_supply_set_status(1, 'delivered');
CALL sp_supply_set_status(2, 'delivered');
CALL sp_supply_set_status(3, 'delivered');
CALL sp_supply_set_status(4, 'delivered');
CALL sp_supply_set_status(5, 'in_transit');
CALL sp_supply_set_status(5, 'delivered');
COMMIT;

-- Замовлення
-- new -> confirmed -> shipped -> delivered
BEGIN;
CALL sp_set_current_user(3);   -- менеджер з продажу
CALL sp_order_create(1, 4);                        -- order 1
CALL sp_order_add_item(1, 'EL-PHONE-001', 5);
CALL sp_order_add_item(1, 'EL-HEAD-003', 10);
CALL sp_order_add_item(1, 'EL-PHONE-001', 2);      -- той самий товар -> кількість 7
CALL sp_order_set_status(1, 'confirmed');
COMMIT;

BEGIN;
CALL sp_set_current_user(4);   -- комірник
CALL sp_shipment_create(1, 1, 'NP-20450012345');   -- склад Київ
COMMIT;

-- Навушники лише в Одесі, тому відвантаження з Києва має впасти
BEGIN;
CALL sp_set_current_user(4);
DO $$
BEGIN
    CALL scm.sp_shipment_set_status(1, 'shipped');
    RAISE EXCEPTION 'тест не пройшов';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ОЧІКУВАНА ПОМИЛКА: %', SQLERRM;
END;
$$;
ROLLBACK;

-- Довозимо телефони в Одесу й відвантажуємо звідти
BEGIN;
CALL sp_set_current_user(4);
CALL sp_supply_register('K-2026/001', 'EL-PHONE-001', 2, DATE '2026-10-01', 30);   -- 7
CALL sp_supply_set_status(7, 'delivered');
CALL sp_shipment_set_warehouse(1, 2);
CALL sp_shipment_set_status(1, 'shipped');
CALL sp_shipment_set_status(1, 'delivered');
COMMIT;

-- Скасоване замовлення
BEGIN;
CALL sp_set_current_user(3);
CALL sp_order_create(2, 5);                        -- order 2
CALL sp_order_add_item(2, 'CL-JACK-001', 2);
CALL sp_order_add_item(2, 'CL-TSHT-002', 5);
CALL sp_order_set_status(2, 'cancelled');
COMMIT;

-- Нове замовлення, одну позицію прибрали
BEGIN;
CALL sp_set_current_user(3);
CALL sp_order_create(3, 4);                        -- order 3
CALL sp_order_add_item(3, 'CL-TSHT-002', 20);
CALL sp_order_add_item(3, 'CL-JACK-001', 3);
CALL sp_order_add_item(3, 'EL-LAPT-002', 1);
CALL sp_order_remove_item(3, 3);
COMMIT;

-- Soft delete, відновлення, оновлення
BEGIN;
CALL sp_set_current_user(2);   -- керівник
DELETE FROM customer WHERE id = 4;   -- тригер перетворює на soft delete
CALL sp_product_delete('CL-JEAN-003');
CALL sp_product_update('EL-PHONE-001', 'Смартфон Nova X (2026)', 13999.00, 18);
CALL sp_customer_update(2, 'Гончаренко Ірина Василівна', '+380501112233', 'irina.h@gmail.com', 'м. Одеса, вул. Дерибасівська, 7');
CALL sp_employee_delete(8);
COMMIT;

BEGIN;
CALL sp_set_current_user(1);
CALL sp_product_restore('CL-JEAN-003');
COMMIT;
