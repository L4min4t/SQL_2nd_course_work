CREATE ROLE admin WITH SUPERUSER;
\password admin
CREATE DATABASE salary_counter OWNER admin;
\c salary_counter admin;

CREATE TABLE "employee_card" (
  "id" SERIAL PRIMARY KEY,
  "employee_id" int NOT NULL,
  "date" date DEFAULT NOW(),
  "hours_worked" float CHECK ("hours_worked" >= 0 AND "hours_worked" <= 24),
  UNIQUE("date", "employee_id")
);

CREATE TABLE "employee" (
  "id" SERIAL PRIMARY KEY,
  "name" varchar NOT NULL,
  "surname" varchar NOT NULL,
  "patronymic" varchar NOT NULL,
  "subunit_id" int,
  "position_id" int,
  "is_full_time" bool NOT NULL
);

CREATE TABLE "position" (
  "id" SERIAL PRIMARY KEY,
  "name" varchar UNIQUE NOT NULL,
  "wage_per_hour" int NOT NULL CHECK ("wage_per_hour" > 0),
  "wage_per_month" int NOT NULL CHECK ("wage_per_month" > 0),
  "holidays" int NOT NULL CHECK ("holidays" > 0)
);

CREATE TABLE "subunit" (
  "id" SERIAL PRIMARY KEY,
  "name" varchar UNIQUE NOT NULL
);

CREATE TABLE "paycheck" (
  "id" SERIAL PRIMARY KEY,
  "employee_id" int,
  "date" date DEFAULT NULL,
  "salary" float DEFAULT NULL CHECK ("salary" >= 0),
  UNIQUE("date", "employee_id")
);

CREATE TABLE "stuffing_chart" (
  "id" SERIAL PRIMARY KEY,
  "subunit_id" int NOT NULL,
  "position_id" int NOT NULL,
  "quantity" int NOT NULL CHECK ("quantity" > 0),
  "occupied" int NOT NULL CHECK ("occupied" >= 0 AND "occupied" <= "quantity") DEFAULT 0,
  UNIQUE("subunit_id", "position_id")
);

CREATE TABLE "client" (
  "id" SERIAL PRIMARY KEY,
  "name" varchar NOT NULL,
  "surname" varchar NOT NULL,
  "patronymic" varchar NOT NULL,
  "phone" bigint NOT NULL
);

CREATE TABLE "service" (
  "id" SERIAL PRIMARY KEY,
  "description" varchar NOT NULL UNIQUE,
  "subunit_id" int,
  "price" float NOT NULL CHECK ("price" >= 0),
  "amount" int NOT NULL CHECK ("amount" > 0),
  "client_id" int,
  "date" date DEFAULT NOW()
);

CREATE TABLE "schedule" (
  "id" SERIAL PRIMARY KEY,
  "week_day" int CHECK ("week_day" >= 1 AND "week_day" <= 7),
  "subunit_id" int,
  "position_id" int,
  "quantity" int NOT NULL,
  UNIQUE("week_day", "subunit_id", "position_id")
);

ALTER TABLE "employee_card" ADD FOREIGN KEY ("employee_id") REFERENCES "employee" ("id") ON DELETE CASCADE;
ALTER TABLE "employee" ADD FOREIGN KEY ("subunit_id") REFERENCES "subunit" ("id") ON DELETE SET NULL;
ALTER TABLE "employee" ADD FOREIGN KEY ("position_id") REFERENCES "position" ("id") ON DELETE SET NULL;
ALTER TABLE "paycheck" ADD FOREIGN KEY ("employee_id") REFERENCES "employee" ("id") ON DELETE SET NULL;
ALTER TABLE "stuffing_chart" ADD FOREIGN KEY ("subunit_id") REFERENCES "subunit" ("id") ON DELETE CASCADE;
ALTER TABLE "stuffing_chart" ADD FOREIGN KEY ("position_id") REFERENCES "position" ("id") ON DELETE CASCADE;
ALTER TABLE "service" ADD FOREIGN KEY ("subunit_id") REFERENCES "subunit" ("id") ON DELETE SET NULL;
ALTER TABLE "service" ADD FOREIGN KEY ("client_id") REFERENCES "client" ("id") ON DELETE SET NULL;
ALTER TABLE "schedule" ADD FOREIGN KEY ("subunit_id") REFERENCES "subunit" ("id") ON DELETE CASCADE;
ALTER TABLE "schedule" ADD FOREIGN KEY ("position_id") REFERENCES "position" ("id") ON DELETE CASCADE;

-- check if vacancy is available, updating vacancies info after hiring new employee

CREATE FUNCTION hire_employee() RETURNS trigger as $$
DECLARE
	positions_amount int;
	positions_occupied int;
	cur_position int;
	cur_subunit int;
BEGIN
	positions_amount := (SELECT quantity FROM stuffing_chart as c WHERE c.position_id = NEW.position_id AND c.subunit_id = NEW.subunit_id);
	positions_occupied := (SELECT occupied FROM stuffing_chart as c WHERE c.position_id = NEW.position_id AND c.subunit_id = NEW.subunit_id);
	cur_position := NEW.position_id;
	cur_subunit := NEW.subunit_id;
	IF positions_amount > positions_occupied THEN
		UPDATE stuffing_chart as c SET occupied = (c.occupied + 1) WHERE c.position_id = cur_position AND c.subunit_id = cur_subunit;
		RETURN NEW;
	ELSE 
    RAISE EXCEPTION 'such position isnt available in this subunit';
		RETURN NULL;
	END IF;
END
$$ language 'plpgsql';

-- add vacancy after firing an employee

CREATE FUNCTION fire_employee() RETURNS trigger AS $$
BEGIN	
	IF OLD.position_id IS NOT NULL THEN
		UPDATE stuffing_chart as c SET occupied = (c.occupied - 1) WHERE c.position_id = OLD.position_id AND c.subunit_id = OLD.subunit_id;
	END IF;
	RETURN NEW;
END
$$ language 'plpgsql';

-- update vacancies after changing employee position

CREATE FUNCTION change_employee_position() RETURNS trigger AS $$
DECLARE
	positions_amount int;
	positions_occupied int;
BEGIN
	positions_amount := (SELECT quantity FROM stuffing_chart as c WHERE c.position_id = NEW.position_id AND c.subunit_id = NEW.subunit_id);
	positions_occupied := (SELECT occupied FROM stuffing_chart as c WHERE c.position_id = NEW.position_id AND c.subunit_id = NEW.subunit_id);

	IF NEW.position_id IS NOT NULL AND positions_amount >= positions_occupied THEN
		IF OLD.position_id IS NOT NULL THEN
			UPDATE stuffing_chart as c SET occupied = (c.occupied - 1) WHERE c.position_id = OLD.position_id AND c.subunit_id = OLD.subunit_id;
		END IF;
		UPDATE stuffing_chart as c SET occupied = (c.occupied + 1) WHERE c.position_id = NEW.position_id AND c.subunit_id = NEW.subunit_id;
	END IF;
	RETURN NEW;
END
$$ language 'plpgsql';

CREATE TRIGGER on_employee_hire BEFORE INSERT 
ON employee for each row EXECUTE PROCEDURE hire_employee();

CREATE TRIGGER on_employeee_fire AFTER DELETE 
ON employee for each row EXECUTE PROCEDURE fire_employee();

CREATE TRIGGER on_employee_position_update AFTER UPDATE 
ON employee for each row EXECUTE PROCEDURE change_employee_position();

-- salary counter at the end of month

CREATE TABLE "d" (
  	"id" SERIAL PRIMARY KEY,
  	cur_employee_id int,
    cur_month int,
	cur_year int,
    paid_hours float,
    hours_per_day float,
    wage float,
	cur_date date,
	s varchar
);

CREATE OR REPLACE FUNCTION paycheck() RETURNS VOID AS $$
DECLARE
    cur_employee_id int;
    cur_month int := (SELECT EXTRACT(MONTH FROM NOW()));
	cur_year int := (SELECT EXTRACT(YEAR FROM NOW()));
    paid_hours float := 0;
    hours_per_day float := 0;
    wage float := 0;
	cur_date date;
	
BEGIN
    IF (SELECT EXTRACT(DAY FROM (SELECT (date_trunc('MONTH', NOW()) + INTERVAL '1 MONTH - 1 day')))) = (SELECT EXTRACT(DAY FROM NOW())) THEN
        FOR cur_employee_id IN (SELECT employee_id FROM employee_card) LOOP
            IF (SELECT EXISTS(SELECT employee_id FROM paycheck WHERE paycheck.employee_id = cur_employee_id and paycheck.date = NOW()::date)) = false THEN
                IF (SELECT employee.is_full_time FROM "employee" WHERE employee.id = cur_employee_id) = true THEN
                    wage :=  (SELECT "wage_per_month" FROM "position" WHERE position.id = (SELECT "position_id" FROM "employee" WHERE employee.id = cur_employee_id));
                ELSE
					FOR cur_date IN (SELECT "date" FROM "employee_card" WHERE employee_card.employee_id = cur_employee_id) LOOP
						IF cur_month = (SELECT EXTRACT(MONTH FROM cur_date)) AND cur_year = (SELECT EXTRACT(YEAR FROM cur_date)) THEN
							FOR hours_per_day IN (SELECT hours_worked FROM "employee_card" WHERE employee_card.employee_id = cur_employee_id AND employee_card.date = cur_date) LOOP
                        		IF hours_per_day > 8 THEN
                            		paid_hours := paid_hours + (hours_per_day - 8) * 2 + 8;
                        		ELSE
                            		paid_hours := paid_hours + hours_per_day;
                        		END IF;
                    		END LOOP;
						END IF;
                    	wage := paid_hours * (SELECT wage_per_hour FROM "position" WHERE position.id = (SELECT position_id FROM "employee" WHERE employee.id = cur_employee_id));
                    END LOOP;
                END IF;
                INSERT INTO "paycheck" ("employee_id", "date", "salary") VALUES (cur_employee_id, NOW(), wage);
            END IF;
            paid_hours := 0;
			wage := 0;
			hours_per_day := 0;
        END LOOP;
    ELSE
    RAISE EXCEPTION 'Salary can only be counted at the end of month!';
    END IF;
END
$$ language 'plpgsql';

--creating views

CREATE FUNCTION create_views() RETURNS VOID AS $$
BEGIN
  CREATE VIEW "vacancies" AS SELECT "subunit_id", "name", (s.quantity - s.occupied) AS "avaliable", "wage_per_hour", "wage_per_month", "holidays"
  FROM "position" AS "p" INNER JOIN "stuffing_chart" AS "s" ON s.position_id = p.id WHERE (s.quantity - s.occupied) > 0 ORDER BY "subunit_id";
  CREATE OR REPLACE VIEW "holidays" AS SELECT "surname", "name", "patronymic", "employee_id", "date" FROM "employee_card" AS "c" INNER JOIN "employee" AS "e" 
  ON c.employee_id = e.id AND c.hours_worked = 0 ORDER BY e.id, "date";
END
$$ language 'plpgsql';

--

CREATE OR REPLACE FUNCTION update_subunits() RETURNS trigger AS $$
DECLARE
	old_role_name varchar := CONCAT(OLD.name, '_accountant');
  	subunit_name varchar := NEW.name;
	role_name varchar;
	view_name varchar;
BEGIN
  	role_name := CONCAT(subunit_name, '_accountant');
	view_name := CONCAT(OLD.name, '_subunit');
	EXECUTE 'DROP OWNED BY "'||old_role_name||'";';
	EXECUTE 'DROP ROLE "'||old_role_name||'";';
	EXECUTE 'DROP VIEW "'||view_name||'";';
	view_name := CONCAT(subunit_name, '_subunit');
	EXECUTE 'CREATE ROLE "'||role_name||'" LOGIN;
	ALTER ROLE "'||role_name||'" PASSWORD '''||subunit_name||''';';
	EXECUTE 'CREATE OR REPLACE VIEW "'||view_name||'" AS SELECT * FROM (SELECT e.name, e.surname, e.patronymic, e.subunit_id, e.position_id, e.is_full_time, p.date, p.salary 
	FROM employee AS e LEFT OUTER JOIN paycheck AS p ON e.id = p.employee_id) AS all_views WHERE all_views.subunit_id = '||NEW.id||';';
	EXECUTE 'GRANT SELECT ON "'||view_name||'" TO "'||role_name||'";';
	EXECUTE 'GRANT SELECT ON "position" TO "'||role_name||'";';
	EXECUTE 'GRANT SELECT ON "subunit" TO "'||role_name||'";';
	RETURN NEW;
END
$$ language 'plpgsql';

CREATE TRIGGER on_subnit_UPDATE AFTER UPDATE
ON subunit for each row EXECUTE PROCEDURE update_subunits();

--

CREATE OR REPLACE FUNCTION delete_subunits() RETURNS trigger AS $$
DECLARE
  	role_name varchar := CONCAT(OLD.name, '_accountant');
 	view_name varchar := CONCAT(OLD.name, '_subunit');
BEGIN
  	EXECUTE 'DROP OWNED BY "'||role_name||'";';
  	EXECUTE 'DROP ROLE "'||role_name||'";';
	EXECUTE 'DROP VIEW "'||view_name||'";';
	RETURN NEW;
END
$$ language 'plpgsql';

CREATE TRIGGER on_subnit_delete AFTER DELETE
ON subunit for each row EXECUTE PROCEDURE delete_subunits();

--creates subunit views based on inserted subunit

CREATE OR REPLACE FUNCTION create_subunits() RETURNS trigger AS $$
DECLARE
  	subunit_name varchar := NEW.name;
	role_name varchar;
	view_name varchar;
BEGIN    
	role_name := CONCAT(subunit_name, '_accountant');
	view_name := CONCAT(subunit_name, '_subunit');
	EXECUTE 'CREATE ROLE "'||role_name||'" LOGIN;
	ALTER ROLE "'||role_name||'" PASSWORD '''||subunit_name||''';';
	EXECUTE 'CREATE OR REPLACE VIEW "'||view_name||'" AS SELECT * FROM (SELECT e.name, e.surname, e.patronymic, e.subunit_id, e.position_id, e.is_full_time, p.date, p.salary 
	FROM employee AS e LEFT OUTER JOIN paycheck AS p ON e.id = p.employee_id) AS all_views WHERE all_views.subunit_id = '||NEW.id||';';
	EXECUTE 'GRANT SELECT ON "'||view_name||'" TO "'||role_name||'";';
	EXECUTE 'GRANT SELECT ON "position" TO "'||role_name||'";';
	EXECUTE 'GRANT SELECT ON "subunit" TO "'||role_name||'";';
	RETURN NEW;
END
$$ language 'plpgsql';

CREATE TRIGGER on_subnit_insert BEFORE INSERT
ON subunit for each row EXECUTE PROCEDURE create_subunits();

-- won't allow employees with no position to work

CREATE FUNCTION employee_card_insert() RETURNS trigger AS $$
DECLARE
	cur_pos_id int;
BEGIN
 	cur_pos_id := (SELECT position_id FROM employee WHERE NEW.employee_id = employee.id);
	IF cur_pos_id IS NOT NULL THEN
		RETURN NEW;
	END IF;
	RAISE EXCEPTION 'employee without position';
	RETURN NULL;
END
$$ language 'plpgsql';

CREATE TRIGGER on_employee_card_insert BEFORE INSERT OR UPDATE
ON employee_card for each row EXECUTE PROCEDURE employee_card_insert();

-- manage schedule depending on stuffing chart

CREATE OR REPLACE FUNCTION scheduler() RETURNS trigger AS $$
DECLARE
	cur_week_day int := (SELECT EXTRACT(ISODOW FROM NOW()));
	today date := NOW();
	updated_pos_id int := (SELECT position_id FROM employee WHERE id = NEW.employee_id);
	updated_sub_id int := (SELECT subunit_id FROM employee WHERE id = NEW.employee_id);
	e_amount int := (SELECT COUNT(*) FROM employee_card JOIN employee ON employee_card.employee_id = employee.id WHERE "date" = NEW.date AND "position_id" = updated_pos_id AND "subunit_id" = updated_sub_id AND "hours_worked" != 0);
BEGIN
  IF today != NEW.date THEN
  RAISE EXCEPTION 'invalid current day';
	RETURN NULL;
  END IF;
	IF (SELECT quantity FROM schedule WHERE week_day = cur_week_day AND "position_id" = updated_pos_id AND "subunit_id" = updated_sub_id) > e_amount
  OR NEW.hours_worked = 0  THEN
	RETURN NEW;
	ELSE
	RAISE EXCEPTION 'office already has enough employees with this position';
	RETURN NULL;
  END IF;
END
$$ language 'plpgsql';

CREATE TRIGGER schedule_manager BEFORE INSERT
ON employee_card for each row EXECUTE PROCEDURE scheduler();

SELECT create_views();



---------------------------------------------------------------------------------------------------------------------

INSERT INTO "subunit"("name") VALUES('office_1');
INSERT INTO "subunit"("name") VALUES('office_2');
INSERT INTO "subunit"("name") VALUES('office_3');

INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('cashier', 120, 18560, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('cleaner', 160, 23500, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('cook', 190, 30000, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('manager', 550, 90000, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('bicycle courier', 200, 32000, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('car courier', 145, 22650, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('chief cook', 128, 19500, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('kpi student', 143, 21700, 6);
INSERT INTO "position" ("name", "wage_per_hour", "wage_per_month", "holidays") VALUES('guard', 130, 20000, 6);

INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 1, 10);	
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 2, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 3, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 4, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 5, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 6, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 7, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 8, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (2, 9, 10);

INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 2, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 1, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 3, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 4, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 5, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 6, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 7, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 8, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (1, 9, 10);

INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 1, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 2, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 3, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 4, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 5, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 6, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 7, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 8, 10);
INSERT INTO "stuffing_chart" ("subunit_id", "position_id", "quantity") VALUES (3, 9, 10);

INSERT INTO "client" ("name", "surname", "patronymic", "phone") VALUES ('Svetlana', 'Griboedovna', 'Mechehvostova', 50123456789);

INSERT INTO "service" ("description", "subunit_id", "price", "amount", "client_id") VALUES ('meal service', 2, 1500, 3, 1);
INSERT INTO "service" ("description", "subunit_id", "price", "amount", "client_id") VALUES ('delivery service', 3, 500, 10, 1);	
INSERT INTO "service" ("description", "subunit_id", "price", "amount", "client_id") VALUES ('merchandise', 1, 1600, 1, 1);

INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (1, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (2, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (3, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (4, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (5, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (6, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (7, 1, 1, 2);
INSERT INTO "schedule" ("week_day", "subunit_id", "position_id", "quantity") VALUES (5, 2, 6, 2);

INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Arsen', 'Akapyan', 'Igorovich', 1, 1, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Azamat', 'Aitaliyev', 'Geva', 1, 1, false);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Boris', 'Mazur', 'Vasylyovych', 1, 2, true);

INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Cherkash', 'Zavarkin', 'Vasylyovych', 2, 4, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('StaniSlave', 'Lazarev', 'Genadiyevich', 2, 5, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Katerina', 'Yershova', 'Adamovna', 2, 6, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Nikita', 'Tsvetkov', 'Glibovich', 2, 6, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Barbara', 'Bebra', 'Longivna', 2, 6, false);

INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Vyacheslav', 'Lapin', 'Adamovich', 3, 7, true);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Genadij', 'Haharin', 'Stanislavovich', 3, 8, false);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Glib', 'Mishin', 'Borisovich', 3, 8, false);
INSERT INTO "employee" ("name", "surname", "patronymic", "subunit_id", "position_id", "is_full_time") VALUES ('Yevlampij', 'Nosov', 'Arsenovich', 3, 9, true);

INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (1, 1);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (2, 18);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (3, 8);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (4, 8);	
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (5, 0);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (6, 12);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (7, 11);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (8, 8);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (9, 0);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (12, 2);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (10, 2);
INSERT INTO "employee_card" ("employee_id", "hours_worked") VALUES (11, 0);

INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (1, '2021-10-30', 1);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (3, '2021-10-30', 18);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (2, '2021-10-30', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (5, '2021-10-30', 7);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (8, '2021-10-30', 12);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (7, '2021-10-30', 11);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (6, '2021-10-30', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (9, '2021-10-30', 2);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (10, '2021-10-30', 2);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (12, '2021-10-30', 2);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (11, '2021-10-30', 2);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (4, '2021-10-30', 15);

INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (1,  '2021-11-01', 10);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (2,  '2021-11-01', 13);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (5,  '2021-11-01', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (11,  '2021-11-01', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (3,  '2021-11-01', 7);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (6,  '2021-11-01', 6);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (7,  '2021-11-01', 11);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (8,  '2021-11-01', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (9,  '2021-11-01', 2);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (12,  '2021-11-01', 15);

INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (2,  '2021-11-02', 10);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (1,  '2021-11-02', 7);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (5,  '2021-11-02', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (11,  '2021-11-02', 18);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (3,  '2021-11-02', 17);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (6,  '2021-11-02', 3);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (7,  '2021-11-02', 11);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (8,  '2021-11-02', 8);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (9,  '2021-11-02', 9);
INSERT INTO "employee_card" ("employee_id", "date", "hours_worked") VALUES (12,  '2021-11-02', 15);
