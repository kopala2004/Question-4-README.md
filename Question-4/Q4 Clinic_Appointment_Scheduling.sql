-- ICT371 Question 4: Clinic Appointment Scheduling

CREATE SCHEMA IF NOT EXISTS clinic_q4;
SET search_path TO clinic_q4, public;

DROP TABLE IF EXISTS clinic_summary CASCADE;
DROP TABLE IF EXISTS appointments CASCADE;
DROP TABLE IF EXISTS patients CASCADE;
DROP TABLE IF EXISTS doctors CASCADE;

CREATE TABLE patients (
    patient_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE doctors (
    doctor_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE appointments (
    appointment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id INT NOT NULL REFERENCES patients(patient_id),
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id),
    appointment_day DATE NOT NULL,
    slot_time TIME NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('BOOKED','ATTENDED','CANCELLED'))
);

CREATE TABLE clinic_summary (
    summary_date DATE PRIMARY KEY,
    booked_count INT DEFAULT 0,
    attended_count INT DEFAULT 0,
    cancelled_count INT DEFAULT 0
);

INSERT INTO patients(full_name) VALUES
('Mary Banda'),
('John Phiri'),
('Grace Zulu');

INSERT INTO doctors(full_name) VALUES
('Dr Tembo'),
('Dr Mwila'),
('Dr Chanda');

INSERT INTO appointments(patient_id,doctor_id,appointment_day,slot_time,status)
VALUES
(1,1,CURRENT_DATE + 1,TIME '09:00','BOOKED'),
(2,1,CURRENT_DATE + 1,TIME '10:00','BOOKED'),
(3,1,CURRENT_DATE + 1,TIME '11:00','ATTENDED'),
(1,2,CURRENT_DATE + 2,TIME '09:00','BOOKED'),
(2,2,CURRENT_DATE + 2,TIME '10:00','CANCELLED'),
(3,3,CURRENT_DATE + 3,TIME '12:00','BOOKED');

CREATE OR REPLACE FUNCTION fn_daily_load(
    p_doctor_id INT,
    p_day DATE
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM doctors WHERE doctor_id = p_doctor_id
    ) THEN
        RAISE EXCEPTION 'Unknown doctor';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM appointments
    WHERE doctor_id = p_doctor_id
      AND appointment_day = p_day
      AND status <> 'CANCELLED';

    RETURN COALESCE(v_count,0);
END;
$$;

CREATE OR REPLACE FUNCTION trg_check_clash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.slot_time NOT IN (TIME '09:00', TIME '10:00', TIME '11:00', TIME '12:00') THEN
        RAISE EXCEPTION 'Unsupported slot time';
    END IF;

    IF NEW.status <> 'CANCELLED' THEN
        IF EXISTS (
            SELECT 1
            FROM appointments
            WHERE doctor_id = NEW.doctor_id
            AND appointment_day = NEW.appointment_day
            AND slot_time = NEW.slot_time
            AND status <> 'CANCELLED'
            AND appointment_id <> COALESCE(NEW.appointment_id,-1)
        ) THEN
            RAISE EXCEPTION 'Appointment clash detected';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointment_clash
BEFORE INSERT OR UPDATE
ON appointments
FOR EACH ROW
EXECUTE FUNCTION trg_check_clash();

CREATE OR REPLACE PROCEDURE pr_book_appointment(
    p_patient_id INT,
    p_doctor_id INT,
    p_day DATE,
    p_slot TIME
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id=p_patient_id) THEN
        RAISE EXCEPTION 'Invalid patient ID';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM doctors WHERE doctor_id=p_doctor_id) THEN
        RAISE EXCEPTION 'Invalid doctor ID';
    END IF;

    IF p_day < CURRENT_DATE THEN
        RAISE EXCEPTION 'Past dates are not allowed';
    END IF;

    IF p_slot NOT IN (TIME '09:00', TIME '10:00', TIME '11:00', TIME '12:00') THEN
        RAISE EXCEPTION 'Unsupported slot';
    END IF;

    INSERT INTO appointments
    (patient_id,doctor_id,appointment_day,slot_time,status)
    VALUES
    (p_patient_id,p_doctor_id,p_day,p_slot,'BOOKED');
END;
$$;

CREATE OR REPLACE VIEW v_today_appointments AS
SELECT
    p.full_name AS patient_name,
    d.full_name AS doctor_name,
    a.slot_time
FROM appointments a
JOIN patients p ON a.patient_id=p.patient_id
JOIN doctors d ON a.doctor_id=d.doctor_id
WHERE a.appointment_day = CURRENT_DATE
AND a.status='BOOKED';

CREATE INDEX idx_appointments_day_doctor
ON appointments(appointment_day, doctor_id);

EXPLAIN
SELECT *
FROM appointments
WHERE appointment_day = CURRENT_DATE + 1
AND doctor_id = 1;

CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(
    p_day DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO clinic_summary
    (
        summary_date,
        booked_count,
        attended_count,
        cancelled_count
    )
    SELECT
        p_day,
        COUNT(*) FILTER (WHERE status='BOOKED'),
        COUNT(*) FILTER (WHERE status='ATTENDED'),
        COUNT(*) FILTER (WHERE status='CANCELLED')
    FROM appointments
    WHERE appointment_day = p_day
    ON CONFLICT(summary_date)
    DO UPDATE SET
        booked_count = EXCLUDED.booked_count,
        attended_count = EXCLUDED.attended_count,
        cancelled_count = EXCLUDED.cancelled_count;
END;
$$;

-- pg_cron example
-- SELECT cron.schedule(
-- 'clinic-summary-job',
-- '0 1 * * *',
-- $$CALL clinic_q4.pr_refresh_clinic_summary(CURRENT_DATE - 1);$$
-- );
