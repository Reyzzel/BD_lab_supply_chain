SET search_path TO scm, public;

-- Кожен виклик має завершитися помилкою
DO $$
DECLARE
    tests text[] := ARRAY[
        $t$CALL scm.sp_supply_register('K-2025/017', 'EL-HEAD-003', 1, DATE '2026-10-16', 10)$t$,      -- контракт завершився
        $t$CALL scm.sp_supply_register('K-2026/001', 'CL-JACK-001', 1, DATE '2026-10-16', 10)$t$,      -- товару немає в контракті
        $t$CALL scm.sp_supply_register('K-2026/001', 'EL-LAPT-002', 1, DATE '2026-10-16', 40)$t$,      -- ліміт 50, вже 20
        $t$CALL scm.sp_supply_set_status(1, 'planned')$t$,                                              -- поставка завершена
        $t$CALL scm.sp_order_set_status(1, 'cancelled')$t$,                                             -- delivered -> cancelled
        $t$CALL scm.sp_order_add_item(1, 'EL-HEAD-003', 1)$t$,                                          -- замовлення вже не new
        $t$CALL scm.sp_order_create(4, 4)$t$,                                                           -- клієнт видалений
        $t$CALL scm.sp_order_create(1, 8)$t$,                                                           -- працівник звільнений
        $t$CALL scm.sp_order_set_status(3, 'shipped')$t$,                                               -- shipped лише через shipment
        $t$CALL scm.sp_employee_delete(1)$t$,                                                           -- керівник відділу
        $t$UPDATE scm.employee SET mentor_id = 5 WHERE id = 4$t$,                                       -- цикл наставництва
        $t$INSERT INTO scm.clothing VALUES ('EL-PHONE-001', 'M', 'Бавовна')$t$,                        -- порушення спеціалізації
        $t$CALL scm.sp_customer_create('Дубль', NULL, 'IRINA.H@gmail.com', NULL)$t$,                   -- email вже зайнятий
        $t$CALL scm.sp_customer_delete(3)$t$                                                            -- є активне замовлення
    ];
    t text;
    ok integer := 0;
BEGIN
    PERFORM set_config('app.user_id', '1', true);
    FOREACH t IN ARRAY tests LOOP
        BEGIN
            EXECUTE t;
            RAISE WARNING 'ПРАВИЛО НЕ СПРАЦЮВАЛО: %', t;
        EXCEPTION WHEN OTHERS THEN
            ok := ok + 1;
            RAISE NOTICE 'OK: %', SQLERRM;
        END;
    END LOOP;
    RAISE NOTICE '=== Бізнес-правил перевірено: % з %', ok, array_length(tests, 1);
END;
$$;

-- Замовлення
SELECT order_number, status, customer_name, employee_name, items_count, total_amount,
       shipment_status, shipment_warehouse, updated_by_username
  FROM v_order_summary ORDER BY order_number;

-- Залишки
SELECT warehouse_name, product_sku, product_name, quantity FROM v_stock ORDER BY warehouse_id, product_sku;

-- Поставки
SELECT id, contract_number, supplier_name, product_sku, warehouse_name, quantity, amount, status
  FROM v_supply_detail ORDER BY id;

-- Видалені записи
SELECT * FROM v_deleted_records;

-- Функції
SELECT fn_order_total(1)                                        AS order_1_total,
       fn_stock_available('EL-PHONE-001')                       AS phones_in_stock,
       fn_contract_remaining('K-2026/001', 'EL-LAPT-002')       AS laptops_left_by_contract,
       fn_is_contract_valid('K-2025/017')                       AS old_contract_valid,
       fn_supplier_turnover('12345678', DATE '2026-01-01', DATE '2026-12-31') AS techimport_turnover;

SELECT * FROM fn_employee_mentees(1);

-- Історія змін клієнта 2
SELECT changed_at::timestamp(0), operation, username,
       old_data->>'full_name' AS old_name, new_data->>'full_name' AS new_name
  FROM fn_record_history('customer', '2');

-- Soft delete і відновлення в аудиті
SELECT table_name, record_id, operation, username
  FROM v_audit_trail
 WHERE operation IN ('SOFT_DELETE', 'RESTORE')
 ORDER BY id;

-- Запити під GIN / BRIN / Hash / індекс на функції.
-- Таблиці малі, тому seq scan вимкнено
SET enable_seqscan = off;

EXPLAIN (COSTS OFF)
SELECT table_name, record_id, changed_at FROM audit_log WHERE new_data @> '{"status": "cancelled"}';
SELECT table_name, record_id, operation, username
  FROM v_audit_trail WHERE new_data @> '{"status": "cancelled"}';

EXPLAIN (COSTS OFF)
SELECT count(*) FROM audit_log WHERE changed_at >= now() - interval '1 day';

EXPLAIN (COSTS OFF)
SELECT id, full_name FROM customer WHERE phone = '+380671234567';

EXPLAIN (COSTS OFF)
SELECT edrpou, company_name FROM supplier WHERE lower(company_name) = lower('ТОВ "ТЕХНОІМПОРТ"');

RESET enable_seqscan;
