SET search_path TO scm, public;


-- Автоматичне заповнення updated_at / updated_by
CREATE FUNCTION fn_trg_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    NEW.updated_at := now();
    NEW.updated_by := fn_current_user_id();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_department_touch BEFORE INSERT OR UPDATE ON department     FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_employee_touch   BEFORE INSERT OR UPDATE ON employee       FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_customer_touch   BEFORE INSERT OR UPDATE ON customer       FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_order_touch      BEFORE INSERT OR UPDATE ON customer_order FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_product_touch    BEFORE INSERT OR UPDATE ON product        FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_supplier_touch   BEFORE INSERT OR UPDATE ON supplier       FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_contract_touch   BEFORE INSERT OR UPDATE ON contract       FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_warehouse_touch  BEFORE INSERT OR UPDATE ON warehouse      FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_supply_touch     BEFORE INSERT OR UPDATE ON supply         FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();
CREATE TRIGGER trg_shipment_touch   BEFORE INSERT OR UPDATE ON shipment       FOR EACH ROW EXECUTE FUNCTION fn_trg_touch();


-- Soft delete: DELETE перетворюється на UPDATE deleted_at = now()
-- TG_ARGV[0] — стовпець PK. Фізичне видалення: SET app.allow_hard_delete = 'on'
CREATE FUNCTION fn_trg_soft_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    v_pk text := TG_ARGV[0];
BEGIN
    IF current_setting('app.allow_hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;

    IF OLD.deleted_at IS NULL THEN
        EXECUTE format('UPDATE %I.%I SET deleted_at = now() WHERE %I = ($1).%I',
                       TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk, v_pk)
        USING OLD;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_employee_soft_delete  BEFORE DELETE ON employee  FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('id');
CREATE TRIGGER trg_customer_soft_delete  BEFORE DELETE ON customer  FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('id');
CREATE TRIGGER trg_product_soft_delete   BEFORE DELETE ON product   FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('sku');
CREATE TRIGGER trg_supplier_soft_delete  BEFORE DELETE ON supplier  FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('edrpou');
CREATE TRIGGER trg_contract_soft_delete  BEFORE DELETE ON contract  FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('contract_number');
CREATE TRIGGER trg_warehouse_soft_delete BEFORE DELETE ON warehouse FOR EACH ROW EXECUTE FUNCTION fn_trg_soft_delete('id');


-- Журнал аудиту: зберігає старі/нові значення у JSONB
-- TG_ARGV — стовпці PK
CREATE FUNCTION fn_trg_audit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    v_old jsonb;
    v_new jsonb;
    v_op  text := TG_OP;
    v_id  text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD); END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW); END IF;

    IF TG_OP = 'UPDATE' AND v_new ? 'deleted_at' THEN
        IF v_old->>'deleted_at' IS NULL AND v_new->>'deleted_at' IS NOT NULL THEN
            v_op := 'SOFT_DELETE';
        ELSIF v_old->>'deleted_at' IS NOT NULL AND v_new->>'deleted_at' IS NULL THEN
            v_op := 'RESTORE';
        END IF;
    END IF;

    SELECT string_agg(COALESCE(v_new, v_old) ->> a.col, ':' ORDER BY a.ord)
      INTO v_id
      FROM unnest(TG_ARGV) WITH ORDINALITY AS a(col, ord);

    INSERT INTO audit_log (table_name, record_id, operation, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, v_id, v_op, v_old, v_new, fn_current_user_id());

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_department_audit    AFTER INSERT OR UPDATE OR DELETE ON department      FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');
CREATE TRIGGER trg_employee_audit      AFTER INSERT OR UPDATE OR DELETE ON employee        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');
CREATE TRIGGER trg_customer_audit      AFTER INSERT OR UPDATE OR DELETE ON customer        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');
CREATE TRIGGER trg_order_audit         AFTER INSERT OR UPDATE OR DELETE ON customer_order  FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('order_number');
CREATE TRIGGER trg_order_item_audit    AFTER INSERT OR UPDATE OR DELETE ON order_item      FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('order_number', 'line_number');
CREATE TRIGGER trg_product_audit       AFTER INSERT OR UPDATE OR DELETE ON product         FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('sku');
CREATE TRIGGER trg_electronics_audit   AFTER INSERT OR UPDATE OR DELETE ON electronics     FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('product_sku');
CREATE TRIGGER trg_clothing_audit      AFTER INSERT OR UPDATE OR DELETE ON clothing        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('product_sku');
CREATE TRIGGER trg_supplier_audit      AFTER INSERT OR UPDATE OR DELETE ON supplier        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('edrpou');
CREATE TRIGGER trg_contract_audit      AFTER INSERT OR UPDATE OR DELETE ON contract        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('contract_number');
CREATE TRIGGER trg_contract_item_audit AFTER INSERT OR UPDATE OR DELETE ON contract_item   FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('contract_number', 'product_sku');
CREATE TRIGGER trg_warehouse_audit     AFTER INSERT OR UPDATE OR DELETE ON warehouse       FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');
CREATE TRIGGER trg_supply_audit        AFTER INSERT OR UPDATE OR DELETE ON supply          FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');
CREATE TRIGGER trg_stock_audit         AFTER INSERT OR UPDATE OR DELETE ON warehouse_stock FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('warehouse_id', 'product_sku');
CREATE TRIGGER trg_shipment_audit      AFTER INSERT OR UPDATE OR DELETE ON shipment        FOR EACH ROW EXECUTE FUNCTION fn_trg_audit('id');


-- Керівник відділу має працювати в цьому відділі
-- Перевіряється при COMMIT
CREATE FUNCTION fn_ctrg_department_head()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM employee
                    WHERE id = NEW.head_employee_id
                      AND department_id = NEW.id
                      AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Керівник % має бути активним працівником відділу "%"',
                        NEW.head_employee_id, NEW.name;
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_department_head_check
    AFTER INSERT OR UPDATE OF head_employee_id ON department
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_ctrg_department_head();


-- Бізнес-правила працівника
-- Керівника відділу не можна звільнити чи перевести; ментор має бути активним, без циклів
CREATE FUNCTION fn_trg_employee_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
            IF EXISTS (SELECT 1 FROM department WHERE head_employee_id = NEW.id) THEN
                RAISE EXCEPTION 'Працівник % є керівником відділу — спочатку призначте іншого керівника', NEW.id;
            END IF;
            UPDATE employee SET mentor_id = NULL WHERE mentor_id = NEW.id;
        END IF;

        IF NEW.department_id <> OLD.department_id
           AND EXISTS (SELECT 1 FROM department WHERE head_employee_id = NEW.id) THEN
            RAISE EXCEPTION 'Керівника відділу (працівник %) не можна перевести в інший відділ', NEW.id;
        END IF;
    END IF;

    IF NEW.mentor_id IS NOT NULL AND NEW.mentor_id IS DISTINCT FROM
       (CASE WHEN TG_OP = 'UPDATE' THEN OLD.mentor_id END) THEN
        IF NOT EXISTS (SELECT 1 FROM employee WHERE id = NEW.mentor_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Ментор % не існує або звільнений', NEW.mentor_id;
        END IF;

        IF EXISTS (WITH RECURSIVE chain AS (
                       SELECT mentor_id FROM employee WHERE id = NEW.mentor_id
                       UNION
                       SELECT e.mentor_id FROM employee e JOIN chain c ON e.id = c.mentor_id
                   )
                   SELECT 1 FROM chain WHERE mentor_id = NEW.id) THEN
            RAISE EXCEPTION 'Цикл у ланцюжку наставництва: % -> %', NEW.id, NEW.mentor_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employee_guard
    BEFORE INSERT OR UPDATE ON employee
    FOR EACH ROW EXECUTE FUNCTION fn_trg_employee_guard();


-- Неперетинна спеціалізація товару
CREATE FUNCTION fn_trg_product_subtype()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    v_category product_category;
BEGIN
    SELECT category INTO v_category FROM product WHERE sku = NEW.product_sku;

    IF FOUND AND v_category <> TG_ARGV[0]::product_category THEN
        RAISE EXCEPTION 'Товар % має категорію %, його не можна додати як %',
                        NEW.product_sku, v_category, TG_ARGV[0];
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_electronics_subtype BEFORE INSERT OR UPDATE ON electronics
    FOR EACH ROW EXECUTE FUNCTION fn_trg_product_subtype('electronics');
CREATE TRIGGER trg_clothing_subtype    BEFORE INSERT OR UPDATE ON clothing
    FOR EACH ROW EXECUTE FUNCTION fn_trg_product_subtype('clothing');

-- Категорію товару не можна змінити, якщо вже є запис підтипу
CREATE FUNCTION fn_trg_product_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF NEW.category <> OLD.category
       AND (EXISTS (SELECT 1 FROM electronics WHERE product_sku = OLD.sku)
         OR EXISTS (SELECT 1 FROM clothing    WHERE product_sku = OLD.sku)) THEN
        RAISE EXCEPTION 'Неможливо змінити категорію товару %: існують дані підтипу', OLD.sku;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_product_guard BEFORE UPDATE OF category ON product
    FOR EACH ROW EXECUTE FUNCTION fn_trg_product_guard();


-- Замовлення: перевірки при створенні + машина станів
-- new -> confirmed | cancelled; confirmed -> shipped | cancelled; shipped -> delivered
-- shipped/delivered — лише через відвантаження
CREATE FUNCTION fn_trg_order_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'new' THEN
            RAISE EXCEPTION 'Нове замовлення має створюватися зі статусом new';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM customer WHERE id = NEW.customer_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Клієнт % не існує або видалений', NEW.customer_id;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM employee WHERE id = NEW.employee_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Працівник % не існує або звільнений', NEW.employee_id;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (   (OLD.status = 'new'       AND NEW.status IN ('confirmed', 'cancelled'))
                OR (OLD.status = 'confirmed' AND NEW.status IN ('shipped', 'cancelled'))
                OR (OLD.status = 'shipped'   AND NEW.status = 'delivered')) THEN
            RAISE EXCEPTION 'Недопустимий перехід статусу замовлення %: % -> %',
                            NEW.order_number, OLD.status, NEW.status;
        END IF;

        IF NEW.status = 'confirmed'
           AND NOT EXISTS (SELECT 1 FROM order_item WHERE order_number = NEW.order_number) THEN
            RAISE EXCEPTION 'Не можна підтвердити порожнє замовлення %', NEW.order_number;
        END IF;

        IF NEW.status IN ('shipped', 'delivered')
           AND NOT EXISTS (SELECT 1 FROM shipment
                            WHERE order_number = NEW.order_number
                              AND status::text = NEW.status::text) THEN
            RAISE EXCEPTION 'Статус % встановлюється лише через відвантаження', NEW.status;
        END IF;
    END IF;

    IF NEW.customer_id <> OLD.customer_id AND OLD.status <> 'new' THEN
        RAISE EXCEPTION 'Клієнта можна змінити лише у новому замовленні';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_guard
    BEFORE INSERT OR UPDATE ON customer_order
    FOR EACH ROW EXECUTE FUNCTION fn_trg_order_guard();


-- Рядки замовлення: автонумерація, ціна за замовчуванням, захист від змін
CREATE FUNCTION fn_trg_order_item_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    v_order_number integer;
    v_status       order_status;
    v_price        numeric(10,2);
    v_deleted_at   timestamptz;
BEGIN
    v_order_number := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_number ELSE NEW.order_number END;

    SELECT status INTO v_status FROM customer_order WHERE order_number = v_order_number;
    IF v_status IS NOT NULL AND v_status <> 'new' THEN
        RAISE EXCEPTION 'Замовлення % у статусі % — змінювати рядки не можна', v_order_number, v_status;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    SELECT price, deleted_at INTO v_price, v_deleted_at FROM product WHERE sku = NEW.product_sku;
    IF v_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Товар % видалений з каталогу', NEW.product_sku;
    END IF;

    IF TG_OP = 'INSERT' THEN
        NEW.unit_price := COALESCE(NEW.unit_price, v_price);
        IF NEW.line_number IS NULL THEN
            SELECT COALESCE(max(line_number), 0) + 1 INTO NEW.line_number
              FROM order_item WHERE order_number = NEW.order_number;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_order_item_guard
    BEFORE INSERT OR UPDATE OR DELETE ON order_item
    FOR EACH ROW EXECUTE FUNCTION fn_trg_order_item_guard();


-- Поставка: валідація контракту, ліміту, складу; машина станів
-- planned -> in_transit | delivered | rejected; in_transit -> delivered | rejected
CREATE FUNCTION fn_trg_supply_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    v_sign_date    date;
    v_expiry_date  date;
    v_deleted_at   timestamptz;
    v_max_quantity integer;
    v_used         integer;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status IN ('delivered', 'rejected') THEN
            RAISE EXCEPTION 'Поставка % вже завершена (статус %)', OLD.id, OLD.status;
        END IF;
        IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
               (OLD.status = 'planned'    AND NEW.status IN ('in_transit', 'delivered', 'rejected'))
            OR (OLD.status = 'in_transit' AND NEW.status IN ('delivered', 'rejected'))) THEN
            RAISE EXCEPTION 'Недопустимий перехід статусу поставки %: % -> %', OLD.id, OLD.status, NEW.status;
        END IF;
        -- відхилити можна завжди, навіть за анульованим контрактом
        IF NEW.status = 'rejected' THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT c.sign_date, c.expiry_date, c.deleted_at, ci.max_quantity
      INTO v_sign_date, v_expiry_date, v_deleted_at, v_max_quantity
      FROM contract c
      JOIN contract_item ci ON ci.contract_number = c.contract_number
     WHERE c.contract_number = NEW.contract_number
       AND ci.product_sku    = NEW.product_sku;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Товар % не входить у контракт %', NEW.product_sku, NEW.contract_number;
    END IF;
    IF v_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Контракт % анульований', NEW.contract_number;
    END IF;
    IF NEW.delivery_date NOT BETWEEN v_sign_date AND v_expiry_date THEN
        RAISE EXCEPTION 'Дата поставки % поза терміном дії контракту % (% — %)',
                        NEW.delivery_date, NEW.contract_number, v_sign_date, v_expiry_date;
    END IF;
    IF EXISTS (SELECT 1 FROM warehouse WHERE id = NEW.warehouse_id AND deleted_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Склад % закритий', NEW.warehouse_id;
    END IF;

    IF v_max_quantity IS NOT NULL AND NEW.status <> 'rejected' THEN
        SELECT COALESCE(sum(quantity), 0) INTO v_used
          FROM supply
         WHERE contract_number = NEW.contract_number
           AND product_sku     = NEW.product_sku
           AND status <> 'rejected'
           AND id IS DISTINCT FROM NEW.id;

        IF v_used + NEW.quantity > v_max_quantity THEN
            RAISE EXCEPTION 'Перевищено ліміт контракту % для товару %: ліміт %, вже %, запит %',
                            NEW.contract_number, NEW.product_sku, v_max_quantity, v_used, NEW.quantity;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_supply_guard
    BEFORE INSERT OR UPDATE ON supply
    FOR EACH ROW EXECUTE FUNCTION fn_trg_supply_guard();


-- Поставка доставлена -> збільшити залишок на складі
CREATE FUNCTION fn_trg_supply_stock()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF NEW.status = 'delivered' AND (TG_OP = 'INSERT' OR OLD.status <> 'delivered') THEN
        INSERT INTO warehouse_stock (warehouse_id, product_sku, quantity)
        VALUES (NEW.warehouse_id, NEW.product_sku, NEW.quantity)
        ON CONFLICT (warehouse_id, product_sku)
        DO UPDATE SET quantity   = warehouse_stock.quantity + EXCLUDED.quantity,
                      updated_at = now();
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_supply_stock
    AFTER INSERT OR UPDATE OF status ON supply
    FOR EACH ROW EXECUTE FUNCTION fn_trg_supply_stock();


-- Відвантаження: перевірки + машина станів (pending -> shipped -> delivered)
CREATE FUNCTION fn_trg_shipment_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'pending' THEN
            RAISE EXCEPTION 'Відвантаження створюється зі статусом pending';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM customer_order
                        WHERE order_number = NEW.order_number AND status = 'confirmed') THEN
            RAISE EXCEPTION 'Відвантажити можна лише підтверджене замовлення (%)', NEW.order_number;
        END IF;
        IF EXISTS (SELECT 1 FROM warehouse WHERE id = NEW.warehouse_id AND deleted_at IS NOT NULL) THEN
            RAISE EXCEPTION 'Склад % закритий', NEW.warehouse_id;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.warehouse_id <> OLD.warehouse_id AND OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'Склад відвантаження % змінювати вже не можна', OLD.id;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (   (OLD.status = 'pending' AND NEW.status = 'shipped')
                OR (OLD.status = 'shipped' AND NEW.status = 'delivered')) THEN
            RAISE EXCEPTION 'Недопустимий перехід статусу відвантаження %: % -> %', OLD.id, OLD.status, NEW.status;
        END IF;
        IF NEW.status = 'shipped' THEN
            NEW.shipped_at := COALESCE(NEW.shipped_at, now());
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_shipment_guard
    BEFORE INSERT OR UPDATE ON shipment
    FOR EACH ROW EXECUTE FUNCTION fn_trg_shipment_guard();


-- Відвантаження відправлено -> списати залишки, оновити статус замовлення
CREATE FUNCTION fn_trg_shipment_apply()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = scm, public
AS $$
DECLARE
    r record;
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NULL;
    END IF;

    IF NEW.status = 'shipped' THEN
        FOR r IN SELECT product_sku, sum(quantity) AS qty
                   FROM order_item
                  WHERE order_number = NEW.order_number
                  GROUP BY product_sku
        LOOP
            UPDATE warehouse_stock
               SET quantity = quantity - r.qty, updated_at = now()
             WHERE warehouse_id = NEW.warehouse_id
               AND product_sku  = r.product_sku
               AND quantity    >= r.qty;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Недостатньо товару % на складі % (потрібно %, є %)',
                                r.product_sku, NEW.warehouse_id, r.qty,
                                fn_stock_available(r.product_sku, NEW.warehouse_id);
            END IF;
        END LOOP;

        UPDATE customer_order SET status = 'shipped' WHERE order_number = NEW.order_number;

    ELSIF NEW.status = 'delivered' THEN
        UPDATE customer_order SET status = 'delivered' WHERE order_number = NEW.order_number;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_shipment_apply
    AFTER UPDATE OF status ON shipment
    FOR EACH ROW EXECUTE FUNCTION fn_trg_shipment_apply();
