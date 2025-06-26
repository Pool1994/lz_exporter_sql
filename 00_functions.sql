-- Archivo: CalculateMonthsOwed.sql
DELIMITER $$

CREATE FUNCTION `CalculateMonthsOwed`(last_payment_date date) RETURNS int
BEGIN
            DECLARE months_owed INT;
            DECLARE adjusted_last_payment_date DATE;
            DECLARE t_current_date DATE;

            
            SET adjusted_last_payment_date = 
                CASE 
                    WHEN DAY(last_payment_date) < 6 THEN 
                        DATE_FORMAT(last_payment_date, '%Y-%m-06')
                    ELSE 
                        DATE_FORMAT(DATE_ADD(last_payment_date, INTERVAL 1 MONTH), '%Y-%m-06')
                END;

            
            SET t_current_date = 
                CASE 
                    WHEN DAY(NOW()) >= 6 THEN 
                        DATE_FORMAT(NOW(), '%Y-%m-05')
                    ELSE 
                        DATE_FORMAT(DATE_ADD(NOW(), INTERVAL -1 MONTH), '%Y-%m-05')
                END;

            
            SET months_owed = TIMESTAMPDIFF(MONTH, adjusted_last_payment_date, current_date);

            RETURN months_owed;
        END $$

DELIMITER ;



-- Archivo: account_active.sql
DELIMITER $$

CREATE FUNCTION `account_active`(datem date,id_program int,id_advisor int) RETURNS int
BEGIN
        			SET @type_automatic = 1;
                    SET @type_manual = 2;
                    SET @type_zero = 14;
                    SET @type_others = 6;
        
                    SET @method_cashier = 7;
                    SET @modality_monthly = 1;
                    SET @C_PARAGON_PROGRAM = 9;
        
                    SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-06');
                    SET @last_day_of_month = date_add(@first_day_of_month,interval 1 month);
        
                    RETURN (select count(distinct ca.id)
                    from client_accounts ca
                        inner join accounts_status_histories ash on ash.client_acount_id = ca.id
                        inner join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                        inner join recurring_billing_detail  rb on rb.client_acount_id = ca.id and rb.updated_at is null
                        left join transactions t on t.client_acount_id = ca.id and t.status_transaction_id in (1,5,8)
                        and (t.type_transaction_id in (@type_automatic,@type_manual) OR
                        (t.type_transaction_id = @type_manual and t.method_transaction_id not in (@method_cashier)) OR
                        (t.type_transaction_id = @type_others and t.modality_transaction_id = @modality_monthly) 
                        )
                        and t.settlement_date >= @first_day_of_month and t.settlement_date  < @last_day_of_month
                        AND NOT IF(id_program = 0 or id_program is null, false, program_date_for_new_range(id_program, t.settlement_date))

                    where date(ca.created_at) <= DATE_ADD(@first_day_of_month, INTERVAL -6 day)   
                        AND ((aah.advisor_id = id_advisor or id_advisor = 0 or id_advisor is null)
                                and date(aah.created_at) < @last_day_of_month
                                and (aah.updated_at is null or not aah.updated_at <  @last_day_of_month))
                                AND NOT program_date_for_new_range(ca.program_id, @first_day_of_month)
                           and (ca.program_id = id_program or id_program = 0 or id_program is null)     
                           AND ( ca.program_id NOT IN ( @C_PARAGON_PROGRAM ) ) 
                             and ca.migrating = 0 and (date(ca.created_at)<@first_day_of_month or account_paid(ca.id,@first_day_of_month))
                           and (
                                    (
                                        (ash.status in (1,8,9,10) and date(ash.created_at) < @last_day_of_month)
                                        or
                                        (ash.status in (3,5) and ash.created_at >= @first_day_of_month and ash.created_at < @last_day_of_month and t.id is not null  ) 
                                    )
                                    and (ash.updated_at is null
                                            or not ash.updated_at < @last_day_of_month )));
                END $$

DELIMITER ;



-- Archivo: account_paid.sql
DELIMITER $$

CREATE FUNCTION `account_paid`(id_account varchar(36),datem date) RETURNS int
BEGIN
                SET @type_automatic := 1;
                SET @type_manual := 2;
                SET @method_cashier := 7;
                SET @modality_monthly := 1;
                RETURN exists(select id
                    from transactions
                    where type_transaction_id in (@type_automatic, @type_manual)
                        and not ((method_transaction_id is null and modality_transaction_id = @modality_monthly) or (method_transaction_id = @method_cashier and modality_transaction_id = @modality_monthly))
                        and client_acount_id = id_account
                        and settlement_date > DATE_ADD(datem,INTERVAL 4 day)
                        and settlement_date <= DATE_ADD(DATE_ADD(datem,INTERVAL 4 day), INTERVAL 1 month));
            END $$

DELIMITER ;



-- Archivo: assign_operator.sql
DELIMITER $$

CREATE FUNCTION `assign_operator`(f_field varchar(50), f_value text) RETURNS varchar(255) CHARSET latin1
BEGIN
            DECLARE operator VARCHAR(255);
            DECLARE component_id INT;

            select cc.custom_type_component_id into component_id
            from custom_component cc
            where cc.`key` = f_field;

            select case
                when component_id in (1, 2, 6, 7, 13, 14, 15, 16, 17)  then concat('like ', '" % "',f_value,'" % "' )
                when component_id in (3, 9, 11, 12)  then concat('= "', f_value,'"')
                when component_id in (4, 5)  then concat('BETWEEN', true, true )
                when component_id in (8, 10)  then concat('in ', '("', f_value, '")' )
            end into operator;

            RETURN operator;
        END $$

DELIMITER ;



-- Archivo: balance_payments.sql
DELIMITER $$

CREATE FUNCTION `balance_payments`(account_id text, pay_date date) RETURNS json
begin
            declare sale_id int;
            set @balance:=0;
            set @charge = total_charge(account_id);
            set @prev = '';
            set @i:= 0;

            set @type_automatic = 1;
           	set @type_manual = 2;
           	set @type_pfy = 9;
           	set @type_void = 10;
			set @type_refund = 11;
           	set @type_charge_back = 15;
           	set @method_card = 1;
           	set @modality_return = 6;

            SELECT ip.sale_id into sale_id FROM client_accounts ca
                inner join initial_payments ip on ip.account = ca.account
            where ca.id=account_id;

           return (select json_arrayagg(json) from (
                  select json_object('date', date(p.settlement_date),'type', p.type_transaction_id, 'method', p.method_transaction_id, 'modality', p.modality_transaction_id, 'amount', p.amount, 'charge', @charge,'balance', (@balance := @balance + p.amount)) json,
                  date_format(p.settlement_date, "%Y-%m-%d") settlement_date,
                  if(@prev <> date_format(p.settlement_date, "%Y-%m-%d"), @i:=0, @i), @i:=@id+1 as i
                  from (
                      (select t.settlement_date,t.id,t.amount,'Initial payment' type,
                       t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                            inner join initial_payments ip on ip.sale_id = t.sale_id
                            inner join client_accounts ca on ip.account = ca.account
                        where t.sale_id = sale_id
                            and t.type_transaction_id not in (@type_void,@type_refund)
                            and status_transaction_id in (1,5))
                        union
                        (select t.settlement_date,t.id,t.amount,'Initial payment' type,
                        t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                            inner join initial_payments ip on ip.transactions_id = t.id
                            inner join client_accounts ca on ip.account = ca.account
                        where ca.id = account_id
                            and t.type_transaction_id not in (@type_void,@type_refund)
                            and status_transaction_id in (1,5))
                        union
                        (select t.settlement_date,t.id,t.amount,'Monthly payment' type,
                        t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                        where t.status_transaction_id in (1,5)
                            and t.type_transaction_id in (@type_automatic,@type_manual)
                            and t.client_acount_id = account_id)
                        union
                        (select t.settlement_date,t.id,t.amount,ac.charge type,
                        t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                            inner join additional_charges ac on ac.transactions_id = t.id
                        where ac.client_acount_id = account_id
                            and t.type_transaction_id not in (@type_void,@type_refund)
                            and status_transaction_id in (1,5))
                        union
                        (select t.settlement_date,t.id,t.amount,'Payments of year ' type,
                        t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                        where t.type_transaction_id = @type_pfy
                            and t.method_transaction_id = null
                            and t.modality_transaction_id = null
                            and t.client_acount_id = account_id
                        and status_transaction_id in (1,5))

                        union
                        (select t.settlement_date,t.id,t.amount,'Charge back ' type,
                        t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id
                        from transactions t
                        where t.type_transaction_id = @type_charge_back
                            and t.method_transaction_id = @method_card
                            and t.modality_transaction_id = @modality_return
                            and t.client_acount_id = account_id
                            and status_transaction_id in (1,5,9))
                   ) p, (select @i:=0) i, (select @prev:='') prev order by date_format(p.settlement_date, "%Y-%m-%d") asc) x
                   where (pay_date is null or date(settlement_date) = pay_date));
        END $$

DELIMITER ;



-- Archivo: base_salary_bonification_calculation.sql
DELIMITER $$

CREATE FUNCTION `base_salary_bonification_calculation`(_employee_id VARCHAR(255), _month int,_year int) RETURNS json
BEGIN
            DECLARE _real_salary DECIMAL(10, 2);
            DECLARE _start_date date;
      	    DECLARE _end_date date;
            DECLARE _company_id INT DEFAULT 0;
            DECLARE _base_salary_formated decimal(10,2);
            DECLARE _bonification_salary DECIMAL(10, 2);
            DECLARE _base_salary DECIMAL(10, 2);
            DECLARE _minimun_salary decimal(10,2);
            DECLARE _bonification_salary_formated decimal(10,2);
            DECLARE error_message TEXT DEFAULT 'Error';

		        /* get employee salary */
           	SELECT ifnull(get_employee_salary(_employee_id, _month, _year),0) into _real_salary;

            /* get employee start_date */
            SELECT start_date, end_date  into _start_date, _end_date from employees e WHERE e.id=_employee_id;

            /* get employee company_id*/
            SELECT companie_id INTO _company_id FROM employees WHERE id = _employee_id;



            IF _company_id IS NULL THEN
                SET error_message = concat('Error: Employee doesnt have a company id ' , _employee_id);
                SIGNAL SQLSTATE '45000' SET message_text = error_message;
            END IF;


            /* get employee porcentaje*/
            SELECT `value` INTO _base_salary FROM
            (
              ( -- Get the base salary according to given month and year
                SELECT `value`
                FROM payment_settings
                WHERE slug = 'SEP'
                  AND updated_by IS NULL
                  AND updated_at IS NULL
                  AND MONTH(created_at) < _month
                  AND YEAR(created_at) <= _year
                  AND companie_id = _company_id
                ORDER BY created_at DESC
                LIMIT 1
              )
              UNION
              ( -- Default base salary if there is not previous data
                SELECT `value`
                FROM payment_settings
                WHERE slug = 'SEP'
                  AND updated_by IS NULL
                  AND updated_at IS NULL
                  AND companie_id = _company_id
                ORDER BY created_at ASC
                LIMIT 1
              )
            ) AS psx
            LIMIT 1;
            SELECT `value` INTO _bonification_salary FROM
            (
              ( -- Get the bonification salary according to given month and year
                SELECT `value`
                FROM payment_settings
                WHERE slug = 'BEP'
                  AND updated_by IS NULL
                  AND updated_at IS NULL
                  AND MONTH(created_at) < _month
                  AND YEAR(created_at) <= _year
                  AND companie_id = _company_id
                ORDER BY created_at DESC
                LIMIT 1
              )
              UNION
              ( -- Default bonification salary if there is not previous data
                SELECT `value`
                FROM payment_settings
                WHERE slug = 'BEP'
                  AND updated_by IS NULL
                  AND updated_at IS NULL
                  AND companie_id = _company_id
                ORDER BY created_at ASC
                LIMIT 1
              )
            ) AS psx
            LIMIT 1;
           SELECT `value` INTO _minimun_salary  FROM
            (
              ( -- Get the bonification salary according to given month and year
            SELECT `value`
                FROM payment_settings
                WHERE slug = 'MS'
                  AND updated_by IS NULL
                  AND updated_at IS NULL
                  AND MONTH(created_at) < _month
                  AND YEAR(created_at) <= _year
                  AND companie_id = _company_id
                ORDER BY created_at DESC
                LIMIT 1
              )
              UNION
              ( -- Default bonification salary if there is not previous data
                SELECT 1130 `value`
              )
            ) AS psx
            LIMIT 1;


            set @amountxporcentaje= ifnull(CAST((_real_salary * ( _base_salary / 100 )) AS DECIMAL(10,2)),0.00);
            IF(@amountxporcentaje<=_minimun_salary and @amountxporcentaje >0 ) then
              select _minimun_salary into  _base_salary_formated;
            ELSE
              select CASE
                      WHEN (_real_salary * (_base_salary / 100) %100>=1 and _real_salary * (_base_salary / 100)%100<=50)THEN
                      (FLOOR((_real_salary * (_base_salary / 100))/100)*100) + 50
                      WHEN (_real_salary * (_base_salary / 100)%100>50 and _real_salary * (_base_salary / 100)%100<=100) THEN
                      CEIL((_real_salary * (_base_salary / 100)) / 100) * 100
                      ELSE _real_salary * (_base_salary / 100)
                      END AS rounded_salary into _base_salary_formated;
            END IF;

    	      set _bonification_salary_formated = _real_salary-_base_salary_formated;



            IF((MONTH(_start_date)=_month and YEAR(_start_date)=_year) OR (MONTH(_end_date)=_month and YEAR(_end_date)=_year)) then
          	 	set  @working_days= (SELECT DATEDIFF(LAST_DAY(_start_date), _start_date) + 1);
				      IF(MONTH(_end_date)=_month and YEAR(_end_date)=_year) THEN
           			set  @working_days= (SELECT DATEDIFF(_end_date, LAST_DAY(_end_date - interval 1 month) + interval 1 day) + 1);
       			  END IF;

       			  set  @base_salary_formated_special=   _base_salary_formated/30 *  @working_days;
              set _bonification_salary_formated = _real_salary/30* @working_days-_base_salary_formated/30*@working_days;
              set _base_salary_formated = @base_salary_formated_special;

              IF (_real_salary/30*@working_days) <= _minimun_salary then

                set @entro =1;
                set _base_salary_formated=(_real_salary/30*@working_days);
                set _bonification_salary_formated = 0;
              END IF;

            END IF;

            RETURN JSON_OBJECT('base_salary', ifnull(CAST(_base_salary_formated  AS DECIMAL(10,2)),0.00),
           			'bonification_salary', ifnull(CAST((_bonification_salary_formated) AS DECIMAL(10,2)) ,0.00),
           		     'porcentaje', ifnull(CAST((_real_salary * ( _base_salary / 100 )) AS DECIMAL(10,2)),0.00),
           		     'salario_real', ifnull(_real_salary,0.00),
           		     'dias',@working_days
           			);
        END $$

DELIMITER ;



-- Archivo: calculate_average_salary_in_range.sql
DELIMITER $$

CREATE FUNCTION `calculate_average_salary_in_range`( _employee_id VARCHAR(36), _start_date DATE, _end_date DATE ) RETURNS decimal(10,2)
BEGIN

    DECLARE _average_salary DECIMAL(8, 2);
    DECLARE _total_salary_in_range DECIMAL(8, 2) DEFAULT 0;
    DECLARE _months_counter INT DEFAULT 0;
    DECLARE _start_date_copy DATE;

    SET _start_date_copy = _start_date;

    WHILE( YEAR(_start_date_copy) < YEAR(_end_date) OR (YEAR(_start_date_copy) = YEAR(_end_date) AND MONTH(_start_date_copy) <= MONTH(_end_date))) DO
        SET _total_salary_in_range = _total_salary_in_range + get_employee_salary( _employee_id, MONTH(_start_date_copy), YEAR(_start_date_copy) );
        SET _start_date_copy = DATE_ADD( _start_date_copy, INTERVAL 1 MONTH );
        SET _months_counter = _months_counter + 1;
    END WHILE;

    RETURN IF( _months_counter = 0, 0,CAST(_total_salary_in_range / _months_counter AS DECIMAL(10,2) )  );

    END $$

DELIMITER ;



-- Archivo: calculate_business_commission.sql
DELIMITER $$

CREATE FUNCTION `calculate_business_commission`(_sale_id INT) RETURNS decimal(10,2)
BEGIN
                DECLARE _state_fee DECIMAL(10, 2);
                DECLARE _amg_fee DECIMAL(10, 2);
                DECLARE _initial_payment DECIMAL(10, 2);
                DECLARE _ip_percentage DECIMAL(10, 2);
                DECLARE _ratio DECIMAL(10, 2);
                DECLARE _commission DECIMAL(10, 2);
                DECLARE _state_id INT;


                SET _state_id = (
                	SELECT state_id
                    FROM sales
                    WHERE id = _sale_id
                    LIMIT 1);

                IF _state_id IS NULL THEN
                   RETURN 0;
                END IF;

                SELECT amount
                INTO _initial_payment
                FROM initial_payments
                WHERE sale_id = _sale_id
                LIMIT 1;

                IF _initial_payment IS NULL THEN
                   RETURN 0;
                END IF;

                SELECT state_fee, amg_fee
                INTO _state_fee, _amg_fee
                FROM fees
                WHERE state_id = _state_id
                LIMIT 1;

                IF _state_fee IS NULL THEN
                   RETURN 0;
                END IF;

                IF _amg_fee IS NULL OR _amg_fee = 0 THEN
                   RETURN 0;
                END IF;

                SET _ratio = (_state_fee / _amg_fee) * 100;

                SET _ip_percentage = (
                    SELECT new_value
                    FROM tracking_percentage_commission_business
                    ORDER BY id DESC
                    LIMIT 1
                );

                IF _ip_percentage IS NULL THEN
                   RETURN 0;
                END IF;

                SET _commission = _initial_payment * (100 - _ratio) * _ip_percentage / 100 / 100;

                RETURN _commission;
            END $$

DELIMITER ;



-- Archivo: calculate_contributions_pension_fund.sql
DELIMITER $$

CREATE FUNCTION `calculate_contributions_pension_fund`(_employee_id char(36),_month int,_year int) RETURNS json
BEGIN

		 DECLARE _percentage_basic_salary INT DEFAULT 0;
	      DECLARE _ONP_contribution  DECIMAL (10,2);
     	  DECLARE _AFP_contribution  DECIMAL (10,2);
     	  DECLARE _AFP_commissions  DECIMAL (10,2);
     	  DECLARE _AFP_insurance DECIMAL (10,2);
     	  DECLARE _gross_salary  DECIMAL (10,2);
      	  DECLARE _base_salary  DECIMAL (10,2);


	    SELECT JSON_EXTRACT(base_salary_bonification_calculation(_employee_id, _month, _year),
                    '$.base_salary')
                    INTO _base_salary;

	      SET _ONP_contribution=(
	     				SELECT IF (pf.`type` = 'public', ROUND(( _base_salary * (pf.mandatory_contribution / 100)),2), 0)
	     				FROM employees e
	     				INNER JOIN pension_fund pf ON pf.id= e.pension_fund_id
	     				WHERE e.id = _employee_id
	     				);

	     SET _AFP_contribution=(
	     				SELECT IF (pf.`type` = 'private', ROUND(( _base_salary * (pf.mandatory_contribution / 100)),2), 0 )
	     				FROM employees e
	     				INNER JOIN pension_fund pf ON pf.id= e.pension_fund_id
	     				WHERE e.id = _employee_id
	     				);

	     SET _AFP_commissions=(
	     				SELECT IF (pf.`type` = 'private', ROUND(( _base_salary * (pf.commissions / 100)),2), 0 )
	     				FROM employees e
	     				INNER JOIN pension_fund pf ON pf.id= e.pension_fund_id
	     				WHERE e.id = _employee_id
	     				);

	     SET _AFP_insurance=(
	     				SELECT IF (pf.`type` = 'private', ROUND(( _base_salary * (pf.insurance / 100)),2), 0 )
	     				FROM employees e
	     				INNER JOIN pension_fund pf ON pf.id= e.pension_fund_id
	     				WHERE e.id = _employee_id
	     				);

	    RETURN JSON_OBJECT(
			'ONP_CONTRIBUTION', IFNULL(cast(_ONP_contribution as decimal(10,2)), 0),
			'AFP_CONTRIBUTION', IFNULL(cast(_AFP_contribution as decimal(10,2)) , 0),
			'AFP_COMISSIONS', IFNULL(cast(_AFP_commissions as decimal(10,2)) , 0),
			'AFP_INSURANCE', IFNULL(cast(_AFP_insurance as decimal(10,2)) , 0)
		);
        END $$

DELIMITER ;



-- Archivo: calculate_hours_worked.sql
DELIMITER $$

CREATE FUNCTION `calculate_hours_worked`(
            _month int,
            _employee int,
            _year int
        ) RETURNS int
BEGIN
            DECLARE _hours_worked int;
            DECLARE _current_date DATE;

            SELECT DATE_FORMAT(CONCAT(_year, '-', _month, '-01'), '%Y-%m-%d') INTO _current_date;
            SELECT SUM(total_hours_validate) into _hours_worked  FROM (
                SELECT
                MAX(employee_var) AS employee_var,
                MAX(employee_id) AS employee_id,
                MAX(date_mark) AS date_mark,
                MAX(num_marks) AS num_marks,
                ANY_VALUE(DATE_FORMAT(first_mark, '%H:%i:%s')) AS first_mark,
                ANY_VALUE(DATE_FORMAT(second_mark, '%H:%i:%s')) AS second_mark,
                ANY_VALUE(DATE_FORMAT(third_mark, '%H:%i:%s')) AS third_mark,
                ANY_VALUE(DATE_FORMAT(fourth_mark, '%H:%i:%s')) AS fourth_mark,
                ANY_VALUE(DATE_FORMAT(last_mark, '%H:%i:%s')) AS last_mark,
                ANY_VALUE(DATE_FORMAT(DATE_ADD('1900-01-01 00:00:00', INTERVAL working_hours SECOND),'%H:%i:%s')) AS working_hours,
                ANY_VALUE(first_mark) AS date_first_mark,
                MAX(hours_to_work) AS hours_to_work,
                ANY_VALUE(working_mark_hours_valid) AS working_mark_hours_valid,
                ANY_VALUE(working_hours_valid_late_validation) AS working_hours_valid_late_validation,
                MAX(tolerance) AS tolerance,
                ANY_VALUE(overtime) AS overtime,
                ANY_VALUE(overtime_approved) AS overtime_approved,
                MAX(holidays) AS holidays,
                ANY_VALUE(working_hours_rounded) AS working_hours_rounded,
                ANY_VALUE(  IF(working_hours_valid_late_validation < hours_to_work, 
                            IF(working_hours_valid_late_validation < 0, 0, working_hours_valid_late_validation), 
                            hours_to_work
                        ) 
            ) + MAX(holidays) + ANY_VALUE(overtime_approved)  AS total_hours_validate,
                ANY_VALUE(type_justificate_approved) AS type_justificate_approved,
                ANY_VALUE(
                    CASE
                        WHEN date_mark > date(now())
                        AND holidays <= 0 THEN 'NOT REGISTER'
                        WHEN holidays > 0 THEN 'HOLIDAYS'
                        WHEN if(get_employee_schedule(employee_id,STR_TO_DATE(CONCAT(first_mark), '%Y-%m-%d %H:%i:%s'))>7,num_marks !=4 and num_marks !=0,num_marks !=2 and num_marks !=0)
                        AND type_justificate_approved is  null  AND (tolerance IS null or tolerance ='good') THEN 'INCONSISTENCY'
                        WHEN num_marks = 0
                        AND type_justificate_approved IS NULL THEN 'UNMARKED'
                        WHEN if(get_employee_schedule(employee_id,STR_TO_DATE(CONCAT(first_mark), '%Y-%m-%d %H:%i:%s'))>7,num_marks = 4,num_marks = 2)
                        AND (tolerance IS null or tolerance ='good')
                        AND type_justificate_approved IS NULL THEN 'ATTENDANCE'
                        WHEN tolerance ='late'
                        AND type_justificate_approved IS NULL
                        THEN 'DELAY'
                        WHEN type_justificate_approved IS NOT NULL THEN UPPER(type_justificate_approved)
                        ELSE type_justificate_approved
                    END
                ) AS type
                FROM(
                    SELECT 
                    employee_var,
                    employee_id,
                    date_mark,
                    marks num_marks,
                    first_mark,
                    second_mark,
                    third_mark,
                    fourth_mark,
                    exit_work AS last_mark,
                    get_employee_schedule(employee_id, date_mark) AS hours_to_work,
                    FLOOR(
                        CASE 
                    
                    
                        WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) >= 480 AND DAYOFWEEK(date_mark) NOT IN (1,7) THEN 480
                        WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) >= 360 THEN 360
                        ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                    / 60) working_mark_hours_valid,
                    (	CASE 
                        WHEN entry_mark > exit_work THEN 0 
                        ELSE TIMESTAMPDIFF(SECOND, first_mark, exit_work) END
                    ) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 60 * 60) AS working_hours,
                    FLOOR(
                        CASE 
                        WHEN entry_mark > exit_work THEN 0 
                        ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                    / 60) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 1) AS working_hours_valid_late_validation,
                    tolerance,
                    FLOOR(
                            CASE WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) > working_hours THEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) - working_hours
                            ELSE 0 END
                        / 60
                    ) AS overtime,
                    IFNULL(
                        (
                            SELECT sum(o.hours)
                            FROM justifications j
                            INNER JOIN overtime o ON o.id_justification = j.id
                            WHERE
                                j.type_justification in ( select id from type_justifications )
                                AND o.process_overtime in (4, 6)
                                AND j.id_employee = employee_id
                                AND o.`date` = date_mark
                                and o.deleted_at is null
                        ),
                        0
                    ) overtime_approved,
                    IFNULL(
                        (
                            SELECT
                                GROUP_CONCAT(tj.name)
                            FROM
                                justifications j
                                INNER JOIN overtime o ON o.id_justification = j.id
                                join type_justifications tj on j.type_justification = tj.id
                            WHERE
                                j.type_justification in (
                                    select
                                        id
                                    from
                                        type_justifications
                                )
                                AND o.process_overtime in (4, 6)
                                AND j.id_employee = employee_id
                                AND o.`date` = date_mark
                                and o.deleted_at is null
                        ),
                        null
                    ) type_justificate_approved,
                    0 holidays,
                    FLOOR(
                        CASE 
                        WHEN entry_mark > exit_work THEN 0 
                        ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                    / 60) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 1) AS  working_hours_rounded
                    FROM (SELECT
                            DISTINCT
                            ea.user_id AS employee_id,
                            e.number AS employee_var,
                            ANY_VALUE((SELECT 
                                    tolerance
                                FROM employees_attendance
                                WHERE user_id = ea.user_id AND date(mark_time) = DATE(MIN(ea.mark_time))
                                ORDER BY mark_time ASC
                                LIMIT 1)) AS tolerance,
                            CASE
                                WHEN TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) >= 480 THEN 540
                                WHEN TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) >= 360 THEN 360
                                ELSE TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) END 
                            AS working_hours,
                    
                            ANY_VALUE(
                            ( SELECT  COUNT(*) FROM
                                    employees_attendance AS e2
                                WHERE
                                    e2.user_id = ea.user_id AND
                                    date(e2.mark_time) = date(ea.mark_time))
                            ) AS marks,
                            DATE(ea.mark_time) AS date_mark,
                            ANY_VALUE(
                            CASE 
                                WHEN (SELECT 
							tolerance
						FROM employees_attendance
						WHERE user_id = ea.user_id AND date(mark_time) = DATE(MIN(ea.mark_time))
						ORDER BY mark_time ASC
						LIMIT 1) = 1 THEN DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00')
                                WHEN (SELECT 
							tolerance
						FROM employees_attendance
						WHERE user_id = ea.user_id AND date(mark_time) = DATE(MIN(ea.mark_time))
						ORDER BY mark_time ASC
						LIMIT 1) = 2 AND HOUR(MIN(ea.mark_time)) > HOUR(s.work_start_time) THEN DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00')
                                WHEN (SELECT 
							tolerance
						FROM employees_attendance
						WHERE user_id = ea.user_id AND date(mark_time) = DATE(MIN(ea.mark_time))
						ORDER BY mark_time ASC
						LIMIT 1) = 2 THEN DATE_ADD(DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00'), INTERVAL 1 HOUR)
                                ELSE MIN(ea.mark_time)
                            END
                            ) AS entry_mark,
                            MIN(ea.mark_time) AS first_mark,
                            ANY_VALUE(
                                (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id 
                                    AND date(mark_time) = DATE(ea.mark_time)
                                    LIMIT 1 OFFSET 1
                                )
                            ) AS second_mark,
                            ANY_VALUE(
                                (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id
                                    AND date(mark_time) = DATE(ea.mark_time)
                                    LIMIT 1 OFFSET 2
                                )
                            ) AS third_mark,
                            ANY_VALUE(
                                (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id
                                    AND date(mark_time) = DATE(ea.mark_time)
                                    LIMIT 1 OFFSET 3
                                )
                            ) AS fourth_mark,
                            MAX(ea.mark_time) AS exit_work
                        FROM 
                            employees_attendance ea
                        JOIN employees e ON ea.user_id = e.id_user
                        JOIN
                            employees_schedule s ON e.id = s.employee_id
                            AND DAYOFWEEK(ea.mark_time) = s.day_of_the_week
                        JOIN user_module um ON um.user_id = e.id_user
                        WHERE
                            DATE(ea.mark_time) BETWEEN _current_date AND last_day(_current_date)
                            AND ea.user_id = _employee
                        GROUP BY
                            ea.user_id,
                            DATE(ea.mark_time),
                            employee_var,
                            working_hours
                    ) AS attendance
                    UNION ALL
                        select 
                        e.`number` employee_var, 
                        e.id_user employee_id,
                        a.Date date_mark,
                        0 num_marks,
                        NULL first_mark,
                        NULL second_mark,
                        NULL third_mark,
                        NULL fourth_mark,
                        NULL last_mark,
                        get_employee_schedule(e.id_user, a.Date) AS hours_to_work,
                        0 working_mark_hours_valid,
                        0 working_hours_valid_late_validation,
                        0 working_hours,
                        NULL tolerance,
                        0 overtime,
                        IFNULL(
                            (
                                SELECT sum(o.hours)
                                FROM justifications j
                                INNER JOIN overtime o ON o.id_justification = j.id
                                WHERE
                                    j.type_justification in ( select id from type_justifications )
                                    AND o.process_overtime in (4, 6)
                                    AND j.id_employee = e.id_user
                                    AND o.`date` = a.Date
                                    and o.deleted_at is null
                            ),
                            0
                        ) overtime_approved,
                        IFNULL(
                            (
                                SELECT
                                    GROUP_CONCAT(tj.name)
                                FROM
                                    justifications j
                                    INNER JOIN overtime o ON o.id_justification = j.id
                                    join type_justifications tj on j.type_justification = tj.id
                                WHERE
                                    j.type_justification in (
                                        select
                                            id
                                        from
                                            type_justifications
                                    )
                                    AND o.process_overtime in (4, 6)
                                    AND j.id_employee = e.id_user
                                    AND o.`date` = a.Date
                                    and o.deleted_at is null
                            ),
                            null
                        ) type_justificate_approved,
                        CASE
                            WHEN h.month IS NULL THEN 0
                            WHEN DAYOFWEEK(STR_TO_DATE(CONCAT(h.year, '-', h.month, '-', h.day), '%Y-%m-%d')) IN (1, 7) THEN 6
                            ELSE 8
                        END AS holidays,
                        0 working_hours_rounded
                        from (
                            select last_day(_current_date) - INTERVAL (a.a + (10 * b.a) + (100 * c.a)) DAY as Date
                            from (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as a
                            cross join (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as b
                            cross join (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as c
                        ) a 
                        left join attendance_holidays h ON a.Date = CONCAT(ifnull(h.year, _year),'-',h.month,'-',h.day)
                        and a.Date <= CONCAT(ifnull(h.year, _year),'-',h.month,'-',h.day)
                        and h.deleted_at is null
                        cross join employees e on e.id_user = _employee
                        where a.Date between _current_date and last_day(_current_date)
                ) AS subconsulta
                GROUP BY date_mark
                ORDER BY date_mark
            ) AS subconsulta2;

            RETURN _hours_worked;
    END $$

DELIMITER ;



-- Archivo: calculate_max_payment_or_remaining_amount_ds.sql
DELIMITER $$

CREATE FUNCTION `calculate_max_payment_or_remaining_amount_ds`(_client_account_id CHAR(36)) RETURNS decimal(18,2)
BEGIN
                            DECLARE amount DECIMAL(18,2) DEFAULT 0;
                            SET @debsolutionProgramId := 4;
                        
                           SELECT  ROUND(COALESCE(SUM(dlc.balance), 0) * 0.8, 2)
                           INTO amount
                        FROM client_accounts ca
                            JOIN clients c ON c.id = ca.client_id
                            JOIN sales s ON s.client_id = c.id AND s.program_id = ca.program_id AND s.status_id =4 AND s.program_id = @debsolutionProgramId AND s.annul =0 AND s.annulled_at IS NULL
                            JOIN ds_list_credits dlc ON dlc.client_id = s.client_id or dlc.event_id = s.event_id
                            JOIN ds_credits dc ON dc.id = dlc.ds_credit_id
                        where dlc.created_at IS NOT NULL AND ca.id = _client_account_id AND dlc.deleted_at is null
                        AND dlc.ds_credit_id IS NOT NULL AND dc.parents IS NOT NULL AND ca.program_id = @debsolutionProgramId;
                       
                       RETURN amount;
                   END $$

DELIMITER ;



-- Archivo: calculate_missing_hours_employee.sql
DELIMITER $$

CREATE FUNCTION `calculate_missing_hours_employee`(
            _month int,
            _employee int,
            _year int
        ) RETURNS int
BEGIN
        DECLARE _hours_worked int;
        DECLARE _working_hours int;
        DECLARE _current_date DATE;

        SELECT DATE_FORMAT(CONCAT(_year, '-', _month, '-01'), '%Y-%m-%d') INTO _current_date;

    
        SELECT calculate_working_days(_month, _year,_employee) INTO _working_hours;

    
        SELECT SUM(total_hours_validate) into _hours_worked  FROM (
            SELECT
            MAX(employee_var) AS employee_var,
            MAX(employee_id) AS employee_id,
            MAX(date_mark) AS date_mark,
            MAX(num_marks) AS num_marks,
            ANY_VALUE(DATE_FORMAT(first_mark, '%H:%i:%s')) AS first_mark,
            ANY_VALUE(DATE_FORMAT(second_mark, '%H:%i:%s')) AS second_mark,
            ANY_VALUE(DATE_FORMAT(third_mark, '%H:%i:%s')) AS third_mark,
            ANY_VALUE(DATE_FORMAT(fourth_mark, '%H:%i:%s')) AS fourth_mark,
            ANY_VALUE(DATE_FORMAT(last_mark, '%H:%i:%s')) AS last_mark,
            ANY_VALUE(DATE_FORMAT(DATE_ADD('1900-01-01 00:00:00', INTERVAL working_hours SECOND),'%H:%i:%s')) AS working_hours,
            ANY_VALUE(first_mark) AS date_first_mark,
            MAX(hours_to_work) AS hours_to_work,
            ANY_VALUE(working_mark_hours_valid) AS working_mark_hours_valid,
            ANY_VALUE(working_hours_valid_late_validation) AS working_hours_valid_late_validation,
            MAX(tolerance) AS tolerance,
            ANY_VALUE(overtime) AS overtime,
            ANY_VALUE(overtime_approved) AS overtime_approved,
            MAX(holidays) AS holidays,
            ANY_VALUE(working_hours_rounded) AS working_hours_rounded,
            ANY_VALUE(  IF(working_hours_valid_late_validation < hours_to_work, 
                            IF(working_hours_valid_late_validation < 0, 0, working_hours_valid_late_validation), 
                            hours_to_work
                        ) 
            ) + MAX(holidays) + ANY_VALUE(overtime_approved)  AS total_hours_validate,
            ANY_VALUE(type_justificate_approved) AS type_justificate_approved,
            ANY_VALUE(
                CASE
                    WHEN date_mark > date(now())
                    AND holidays <= 0 THEN 'NOT REGISTER'
                    WHEN holidays > 0 THEN 'HOLIDAYS'
                    WHEN if(get_employee_schedule(employee_id,STR_TO_DATE(CONCAT(first_mark), '%Y-%m-%d %H:%i:%s'))>7,num_marks !=4 and num_marks !=0,num_marks !=2 and num_marks !=0)
                    AND type_justificate_approved is  null  AND (tolerance IS null or tolerance ='good') THEN 'INCONSISTENCY'
                    WHEN num_marks = 0
                    AND type_justificate_approved IS NULL THEN 'UNMARKED'
                    WHEN if(get_employee_schedule(employee_id,STR_TO_DATE(CONCAT(first_mark), '%Y-%m-%d %H:%i:%s'))>7,num_marks = 4,num_marks = 2)
                    AND (tolerance IS null or tolerance ='good')
                    AND type_justificate_approved IS NULL THEN 'ATTENDANCE'
                    WHEN tolerance ='late'
                    AND type_justificate_approved IS NULL
                    THEN 'DELAY'
                    WHEN type_justificate_approved IS NOT NULL THEN UPPER(type_justificate_approved)
                    ELSE type_justificate_approved
                END
            ) AS type
            FROM(
                SELECT 
                employee_var,
                employee_id,
                date_mark,
                marks num_marks,
                first_mark,
                second_mark,
                third_mark,
                fourth_mark,
                exit_work AS last_mark,
                get_employee_schedule(employee_id, date_mark) AS hours_to_work,
                FLOOR(
                    CASE 
                
                
                    WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) >= 480 AND DAYOFWEEK(date_mark) NOT IN (1,7) THEN 480
                    WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) >= 360 THEN 360
                    ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                / 60) working_mark_hours_valid,
                (	CASE 
                    WHEN entry_mark > exit_work THEN 0 
                    ELSE TIMESTAMPDIFF(SECOND, first_mark, exit_work) END
                ) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 60 * 60) AS working_hours,
                FLOOR(
                    CASE 
                    WHEN entry_mark > exit_work THEN 0 
                    ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                / 60) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 1) AS working_hours_valid_late_validation,
                tolerance,
                FLOOR(
                        CASE WHEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) > working_hours THEN TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) - working_hours
                        ELSE 0 END
                    / 60
                ) AS overtime,
                IFNULL(
                    (
                        SELECT sum(o.hours)
                        FROM justifications j
                        INNER JOIN overtime o ON o.id_justification = j.id
                        WHERE
                            j.type_justification in ( select id from type_justifications )
                            AND o.process_overtime in (4, 6)
                            AND j.id_employee = employee_id
                            AND o.`date` = date_mark
                            and o.deleted_at is null
                    ),
                    0
                ) overtime_approved,
                IFNULL(
                    (
                        SELECT
                            GROUP_CONCAT(tj.name)
                        FROM
                            justifications j
                            INNER JOIN overtime o ON o.id_justification = j.id
                            join type_justifications tj on j.type_justification = tj.id
                        WHERE
                            j.type_justification in (
                                select
                                    id
                                from
                                    type_justifications
                            )
                            AND o.process_overtime in (4, 6)
                            AND j.id_employee = employee_id
                            AND o.`date` = date_mark
                            and o.deleted_at is null
                    ),
                    null
                ) type_justificate_approved,
                0 holidays,
                FLOOR(
                    CASE 
                    WHEN entry_mark > exit_work THEN 0 
                    ELSE TIMESTAMPDIFF(MINUTE, entry_mark, exit_work) END
                / 60) - IF(DAYOFWEEK(date_mark) IN (1,7), 0, 1) AS  working_hours_rounded
                FROM (SELECT
                        DISTINCT
                        ea.user_id AS employee_id,
                        e.number AS employee_var,
                        ANY_VALUE(ea.tolerance) AS tolerance,
                        CASE
                            WHEN TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) >= 480 THEN 540
                            WHEN TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) >= 360 THEN 360
                            ELSE TIMESTAMPDIFF(MINUTE, s.work_start_time, s.work_end_time) END 
                        AS working_hours,
                
                        ANY_VALUE(
                        ( SELECT  COUNT(*) FROM
                                employees_attendance AS e2
                            WHERE
                                e2.user_id = ea.user_id AND
                                date(e2.mark_time) = date(ea.mark_time))
                        ) AS marks,
                        DATE(ea.mark_time) AS date_mark,
                        ANY_VALUE(
                        CASE 
                            WHEN ea.tolerance = 1 THEN DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00')
                            WHEN ea.tolerance = 2 AND HOUR(MIN(ea.mark_time)) > HOUR(s.work_start_time) THEN DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00')
                            WHEN ea.tolerance = 2 THEN DATE_ADD(DATE_FORMAT(MIN(ea.mark_time), '%Y-%m-%d %H:%00:%00'), INTERVAL 1 HOUR)
                            ELSE MIN(ea.mark_time)
                        END
                        ) AS entry_mark,
                        MIN(ea.mark_time) AS first_mark,
                        ANY_VALUE(
                            (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id 
                                AND date(mark_time) = DATE(ea.mark_time)
                                LIMIT 1 OFFSET 1
                            )
                        ) AS second_mark,
                        ANY_VALUE(
                            (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id
                                AND date(mark_time) = DATE(ea.mark_time)
                                LIMIT 1 OFFSET 2
                            )
                        ) AS third_mark,
                        ANY_VALUE(
                            (	SELECT mark_time FROM employees_attendance WHERE user_id = ea.user_id
                                AND date(mark_time) = DATE(ea.mark_time)
                                LIMIT 1 OFFSET 3
                            )
                        ) AS fourth_mark,
                        MAX(ea.mark_time) AS exit_work
                    FROM 
                        employees_attendance ea
                    JOIN employees e ON ea.user_id = e.id_user
                    JOIN
                        employees_schedule s ON e.id = s.employee_id
                        AND DAYOFWEEK(ea.mark_time) = s.day_of_the_week
                    JOIN user_module um ON um.user_id = e.id_user
                    WHERE
                        DATE(ea.mark_time) BETWEEN _current_date AND last_day(_current_date)
                        AND ea.user_id = _employee
                    GROUP BY
                        ea.user_id,
                        DATE(ea.mark_time),
                        employee_var,
                        working_hours
                ) AS attendance
                UNION ALL
                    select 
                    e.`number` employee_var, 
                    e.id_user employee_id,
                    a.Date date_mark,
                    0 num_marks,
                    NULL first_mark,
                    NULL second_mark,
                    NULL third_mark,
                    NULL fourth_mark,
                    NULL last_mark,
                    get_employee_schedule(e.id_user, a.Date) AS hours_to_work,
                    0 working_mark_hours_valid,
                    0 working_hours_valid_late_validation,
                    0 working_hours,
                    NULL tolerance,
                    0 overtime,
                    IFNULL(
                        (
                            SELECT sum(o.hours)
                            FROM justifications j
                            INNER JOIN overtime o ON o.id_justification = j.id
                            WHERE
                                j.type_justification in ( select id from type_justifications )
                                AND o.process_overtime in (4, 6)
                                AND j.id_employee = e.id_user
                                AND o.`date` = a.Date
                                and o.deleted_at is null
                        ),
                        0
                    ) overtime_approved,
                    IFNULL(
                        (
                            SELECT
                                GROUP_CONCAT(tj.name)
                            FROM
                                justifications j
                                INNER JOIN overtime o ON o.id_justification = j.id
                                join type_justifications tj on j.type_justification = tj.id
                            WHERE
                                j.type_justification in (
                                    select
                                        id
                                    from
                                        type_justifications
                                )
                                AND o.process_overtime in (4, 6)
                                AND j.id_employee = e.id_user
                                AND o.`date` = a.Date
                                and o.deleted_at is null
                        ),
                        null
                    ) type_justificate_approved,
                    CASE
                        WHEN h.month IS NULL THEN 0
                        WHEN DAYOFWEEK(STR_TO_DATE(CONCAT(h.year, '-', h.month, '-', h.day), '%Y-%m-%d')) IN (1, 7) THEN 6
                        ELSE 8
                    END AS holidays,
                    0 working_hours_rounded
                    from (
                        select last_day(_current_date) - INTERVAL (a.a + (10 * b.a) + (100 * c.a)) DAY as Date
                        from (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as a
                        cross join (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as b
                        cross join (select 0 as a union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) as c
                    ) a 
                    left join attendance_holidays h ON a.Date = CONCAT(ifnull(h.year, _year),'-',h.month,'-',h.day)
                    and a.Date <= CONCAT(ifnull(h.year, _year),'-',h.month,'-',h.day)
                    and h.deleted_at is null
                    cross join employees e on e.id_user = _employee
                    where a.Date between _current_date and last_day(_current_date)
            ) AS subconsulta
            GROUP BY date_mark
            ORDER BY date_mark
        ) AS subconsulta2;

    
        set @remove_hours = (_working_hours - _hours_worked);
        RETURN IF(@remove_hours < 0, 0, @remove_hours);
        END $$

DELIMITER ;



-- Archivo: calculate_mp_loan.sql
DELIMITER $$

CREATE FUNCTION `calculate_mp_loan`(amount decimal(11,2), due_number int, payment decimal(11,2)) RETURNS json
begin
            drop temporary table if exists temp_mp;
            create temporary table temp_mp(
                mp decimal(16,2)
            );
            SET @whileNumber=due_number;
            if (payment * due_number > amount) then
                SET @whileNumber = due_number - 1;
            end if;
        
            set @Counter = 1;
            WHILE  @Counter <= @whileNumber DO
                insert into temp_mp (mp) values(payment);
                SET @Counter  = @Counter  + 1;
            END WHILE;

            if due_number > @whileNumber then
                insert into temp_mp (mp) values(amount - (payment * @whileNumber));
            end if;
            return (select json_arrayagg(JSON_OBJECT('mp',mp)) from temp_mp );
        end $$

DELIMITER ;



-- Archivo: calculate_total_credits_in_payment_schedule.sql
DELIMITER $$

CREATE FUNCTION `calculate_total_credits_in_payment_schedule`(_client_account_id CHAR(36)) RETURNS decimal(18,2)
BEGIN
            DECLARE total DECIMAL(18, 2);
            SET @type_credit = 8;
           
            SELECT COALESCE(SUM(t.amount), 0)
            INTO total
            FROM transactions t
            WHERE t.status_transaction_id IN (1, 5, 8)
            AND t.type_transaction_id = @type_credit
            AND t.client_acount_id = _client_account_id;
        
            RETURN total;
        END $$

DELIMITER ;



-- Archivo: calculate_working_days.sql
DELIMITER $$

CREATE FUNCTION `calculate_working_days`(_mes INT, _ano INT,_employee int) RETURNS int
BEGIN
                DECLARE _fecha_inicio DATE;
                DECLARE _fecha_fin DATE;
                DECLARE _contador_lu_ma_ju_vi INT;
                DECLARE _contador_mi INT;
                DECLARE _contador_sabados INT;
                DECLARE _horas_mes INT;
                DECLARE _start_date DATE;
                DECLARE _end_date DATE;
                DECLARE _total_horas_lunes INT;
                DECLARE _total_horas_mier INT;
                DECLARE _total_horas_sabado INT;
                DECLARE _employee_id VARCHAR(36);

                SELECT e.start_date, e.end_date INTO _start_date, _end_date FROM employees e WHERE e.id_user = _employee;


                SET _fecha_inicio = if(month(_start_date)=_mes and year(_start_date)=_ano ,_start_date,DATE_FORMAT(CONCAT(_ano, '-', _mes, '-01'), '%Y-%m-%d'));
                IF(MONTH(_end_date)=_mes and YEAR(_end_date)=_ano) THEN
           	   	    set _fecha_fin= _end_date;
       			ELSE
                	SET _fecha_fin = LAST_DAY(_fecha_inicio);
           	    END IF;
                SET _contador_lu_ma_ju_vi = 0;
                SET _contador_mi = 0;
                SET _contador_sabados = 0;

                WHILE _fecha_inicio <= _fecha_fin DO
                    IF DAYOFWEEK(_fecha_inicio) = 7 THEN
                        SET _contador_sabados = _contador_sabados + 1;
                    ELSEIF DAYOFWEEK(_fecha_inicio) IN (2, 3, 5, 6) THEN
                        SET _contador_lu_ma_ju_vi = _contador_lu_ma_ju_vi + 1;
                    ELSEIF DAYOFWEEK(_fecha_inicio) = 4 THEN
                        SET _contador_mi = _contador_mi + 1;
                    END IF;
                    SET _fecha_inicio = DATE_ADD(_fecha_inicio, INTERVAL 1 DAY);
                END WHILE;

                SET _employee_id = (SELECT e.id FROM employees e WHERE e.id_user = _employee);
                
                SELECT HOUR(TIMEDIFF(es.work_end_time, es.work_start_time)) -1 INTO _total_horas_lunes 
                FROM employees_schedule es where es.employee_id = _employee_id AND es.day_of_the_week = 2;

                SELECT HOUR(TIMEDIFF(es.work_end_time, es.work_start_time)) -1 INTO _total_horas_mier
                FROM employees_schedule es where es.employee_id = _employee_id AND es.day_of_the_week = 4;

                SELECT HOUR(TIMEDIFF(es.work_end_time, es.work_start_time)) -1 INTO _total_horas_sabado 
                FROM employees_schedule es where es.employee_id = _employee_id AND es.day_of_the_week = 7;

                SET _horas_mes = (_contador_lu_ma_ju_vi * _total_horas_lunes) + (_contador_sabados * IF(_total_horas_sabado IS NULL, 0, 6)) + 
                (_contador_mi * if(_total_horas_mier = 9,  _total_horas_mier + 1, _total_horas_mier));

                SET @horas_null = ((_contador_lu_ma_ju_vi + _contador_mi) * 8) + (_contador_sabados * 6);
                RETURN IF(_employee is null, @horas_null, _horas_mes);
            END $$

DELIMITER ;



-- Archivo: check_has_timeline_by_client_account_id.sql
DELIMITER $$

CREATE FUNCTION `check_has_timeline_by_client_account_id`(clientAccountID char(36)) RETURNS tinyint(1)
BEGIN 
                DECLARE _generated_timeline boolean;
                
                SELECT  cct.generated_timeline into _generated_timeline  from client_account_timeline cct WHERE  cct.client_account_id = clientAccountID;
                
                return _generated_timeline;
            
            END $$

DELIMITER ;



-- Archivo: client_is_debtor_last_payment.sql
DELIMITER $$

CREATE FUNCTION `client_is_debtor_last_payment`(t_year int, t_month int, t_settlement_date date) RETURNS int
BEGIN
            set @datem = if(now() >= date(concat(t_year,'-',t_month,'-','05')),date(concat(t_year,'-',t_month,'-','05')),ADDDATE(date(concat(t_year,'-',t_month,'-','06')), INTERVAL -1 month) );
	
            set @is_debor = (select ((month(t_settlement_date) >= month(@datem) and day(t_settlement_date) > 5 and year(t_settlement_date) = year(@datem)) or (month(t_settlement_date) = if(month(@datem) = 12 ,1,month(@datem)+1) and day(t_settlement_date) <= 5 and year(t_settlement_date) = if(month(@datem) = 12 ,year(@datem)+1,year(@datem)))));

            return @is_debor;
            END $$

DELIMITER ;



-- Archivo: content_has_unseen_notifications.sql
DELIMITER $$

CREATE FUNCTION `content_has_unseen_notifications`(p_content_design_request_id INT) RETURNS tinyint(1)
BEGIN
            DECLARE v_has_unseen_notifications BOOLEAN DEFAULT FALSE;

            SET v_has_unseen_notifications = EXISTS(

                SELECT
                        *
                FROM design_requests contents
                JOIN notification_team_leader_design content_notifications ON content_notifications.request_id = contents.id
                WHERE contents.id = p_content_design_request_id AND content_notifications.updated_at IS NULL

            );

            RETURN v_has_unseen_notifications;
        END $$

DELIMITER ;



-- Archivo: convert_lead_id.sql
DELIMITER $$

CREATE FUNCTION `convert_lead_id`( idaccount char(36)) RETURNS int
BEGIN
	declare id_lead int;
    
	select c.lead_id into id_lead
	from client_accounts ca
		join clients c on c.id = ca.client_id
	where ca.id = idaccount or ca.account = idaccount;
    
RETURN id_lead;
END $$

DELIMITER ;



-- Archivo: convert_module.sql
DELIMITER $$

CREATE FUNCTION `convert_module`(id_program int) RETURNS int
BEGIN
	declare total int;
    select case 
				when id_program = 1  then 3
				when id_program = 2  then 7
				when id_program = 3  then 6
				when id_program = 4  then 5
				when id_program = 5  then 8
				when id_program = 6  then 10
				when id_program = 7  then 11
                when id_program = 9  then 12
                when id_program = 8  then 14
				end into total;
	
RETURN total;
END $$

DELIMITER ;



-- Archivo: convert_program.sql
DELIMITER $$

CREATE FUNCTION `convert_program`(id_module_str VARCHAR(255)) RETURNS int
BEGIN
    DECLARE id_module_int INT;
    DECLARE total INT;

    
    IF id_module_str REGEXP '^[0-9]+$' THEN
        SET id_module_int = CAST(id_module_str AS UNSIGNED);
    ELSE
        SET id_module_int = 2; 
    END IF;

    SELECT CASE
        WHEN id_module_int = 2 THEN 0
        WHEN id_module_int = 3 THEN 1
        WHEN id_module_int = 7 THEN 2
        WHEN id_module_int = 6 THEN 3
        WHEN id_module_int = 5 THEN 4
        WHEN id_module_int = 8 THEN 5
        WHEN id_module_int = 10 THEN 6
        WHEN id_module_int = 11 THEN 7
        WHEN id_module_int = 12 THEN 9
        WHEN id_module_int = 14 THEN 8
        WHEN id_module_int = 22 THEN 3
        WHEN id_module_int = 20 THEN 3
        WHEN id_module_int = 21 THEN 3
        WHEN id_module_int = 23 THEN 3
        WHEN id_module_int = 24 THEN 3
        WHEN id_module_int = 25 THEN 7
        WHEN id_module_int = 26 THEN 3
        WHEN id_module_int = 28 THEN 7
        WHEN id_module_int = 29 THEN 7
        WHEN id_module_int = 30 THEN 7
        ELSE 0 
    END INTO total;

    RETURN total;
END $$

DELIMITER ;



-- Archivo: count_clients_advisor_ce.sql
DELIMITER $$

CREATE FUNCTION `count_clients_advisor_ce`(id_user int, t_program_id int,t_year int, t_month int) RETURNS int
begin
            RETURN  (select  count(distinct aah.client_acount_id) 
                        from client_accounts ca 
                            join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                        where ((aah.advisor_id = id_user)
                        and date(aah.created_at) <= DATE_ADD(concat(t_year,'-',t_month,'-06'), INTERVAL 1 month)
                        and (aah.updated_at is null or not aah.updated_at < DATE_ADD(concat(t_year,'-',t_month,'-06'),interval 1 month) ))
                        and ca.status =1  
                       	and ca.program_id = t_program_id);
                    
        END $$

DELIMITER ;



-- Archivo: count_clients_status_performance_ce.sql
DELIMITER $$

CREATE FUNCTION `count_clients_status_performance_ce`(id_user int, t_status int, t_program_id int,t_year int,t_month int) RETURNS int
begin
        RETURN  (select  count(distinct aah.client_acount_id) 
        from client_accounts ca 
            join accounts_advisors_histories aah on aah.client_acount_id = ca.id
        where ((aah.advisor_id = id_user)
        and date(aah.created_at) <= LAST_DAY(concat(t_year,'-',t_month,'-01'))
        and (aah.updated_at is null or not aah.updated_at < LAST_DAY(concat(t_year,'-',t_month,'-01')) ))
        and ca.status =1  
           and ca.program_id = t_program_id);

                END $$

DELIMITER ;



-- Archivo: count_delete_account.sql
DELIMITER $$

CREATE FUNCTION `count_delete_account`(id_round char(36), id_bureau int, id_type int) RETURNS int
BEGIN
	declare total int;
    if(id_type = 1)then 
    
		select count(distinct(id)) into total from(
            select ca.id
          from cr_accounts_pi ca
            inner join cr_accounts_pi_detail cad on cad.cr_accounts_pi_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where ca.round_letter_id = id_round
          union
          select ca.id
          from cr_accounts_pi ca
            inner join cr_accounts_pi_detail cad on cad.cr_accounts_pi_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where cad.round_letter_id = id_round
          ) x;
        
	elseif(id_type = 2)then 
    
		select count(distinct(id)) into total from(
            select ca.id
          from cr_accounts_in ca
            inner join cr_accounts_in_detail cad on cad.cr_accounts_in_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where ca.round_letter_id = id_round
          union
          select ca.id
          from cr_accounts_in ca
            inner join cr_accounts_in_detail cad on cad.cr_accounts_in_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where cad.round_letter_id = id_round
          ) x;
        
    elseif(id_type = 3)then 
		
		select count(distinct(id)) into total from(
            select ca.id
          from cr_accounts_pr ca
            inner join cr_accounts_pr_detail cad on cad.cr_accounts_pr_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where ca.round_letter_id = id_round
          union
          select ca.id
          from cr_accounts_pr ca
            inner join cr_accounts_pr_detail cad on cad.cr_accounts_pr_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where cad.round_letter_id = id_round
          ) x;
            
        
    elseif(id_type = 4)then 
    
		select count(distinct(id)) into total from(
            select ca.id
          from cr_accounts_ac ca
            inner join cr_accounts_ac_detail cad on cad.cr_accounts_ac_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where ca.round_letter_id = id_round
          union
          select ca.id
          from cr_accounts_ac ca
            inner join cr_accounts_ac_detail cad on cad.cr_accounts_ac_id = ca.id and cad.deleted_at is null and cad.bureau_id = id_bureau
          where cad.round_letter_id = id_round
          ) x;	
        
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: count_files_in_folder.sql
DELIMITER $$

CREATE FUNCTION `count_files_in_folder`(id_folder char(36)) RETURNS int
BEGIN
	declare total int;
	select count(*) into total
    from files_accounts
    where type = 'File'
    and deleted_at is null
    and parent = id_folder
   	and file_name not like '%UNSIGNED%';
RETURN total;
END $$

DELIMITER ;



-- Archivo: count_files_in_folder_projects.sql
DELIMITER $$

CREATE FUNCTION `count_files_in_folder_projects`(id_folder char(36)) RETURNS int
BEGIN
        declare total int;
            select count(*) into total
            from files_project
            where type = 'File'
            and deleted_at is null
            and parent = id_folder
            and file_name not like '%UNSIGNED%';
        RETURN total;
        END $$

DELIMITER ;



-- Archivo: count_ncr_ad.sql
DELIMITER $$

CREATE FUNCTION `count_ncr_ad`(id_user int, date_month int, date_year int, id_type int) RETURNS int
BEGIN
	declare total int;
    
    if(id_type = 0)then 
		SELECT count(*) into total
		FROM tracking_ncrs tn
		where (id_user is null or id_user = 0 or tn.user_id = id_user)
		and tn.status_id = 5
		and tn.status_tk = 8
		and (date(tn.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(tn.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
        and (date(tn.created_at) >= '2020-09-01');
        
     elseif(id_type = 1)then 
		SELECT count(*) into total
		FROM tracking_ncrs tn
		where (id_user is null or id_user = 0 or tn.user_id = id_user)
		and tn.status_id = 5
		and tn.status_tk = 8
        and (date(tn.created_at) >= date(concat(date_year,'-01-01')) and (date(tn.created_at) <= last_day(date(concat(date_year,'-12-01')))))
        and (date(tn.created_at) >= '2020-09-01');
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: count_remaining_month.sql
DELIMITER $$

CREATE FUNCTION `count_remaining_month`(id_program int,p_month int, p_year int) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
            declare count_wo decimal(16,2) default 0;
            declare count_other_programs decimal(16,2) default 0;
            
            set @type_automatic = 1;
            set @type_manual = 2;
            set @type_zero = 14;

            
            set @method_card = 1;
            set @method_cash = 2;
            set @method_cashier = 7;

            
            set @modality_monthly = 1;
            SET @datem = DATE(CONCAT(p_year,'-',p_month,'-01'));
            
            IF program_date_for_new_range(id_program, DATE_ADD(@datem, INTERVAL 1 MONTH)) THEN
                SET @first_day_of_month = DATE(CONCAT(p_year,'-',p_month,'-01'));
                SET @last_day_of_month = LAST_DAY(@first_day_of_month);
            ELSE
                SET @first_day_of_month = DATE(CONCAT(p_year,'-',p_month,'-06'));
                SET @last_day_of_month = date_add(date_add(@first_day_of_month,interval -1 day),interval 1 month);
            END IF;
            
            SET @C_PARAGON_PROGRAM = 9;

            RETURN (
                SELECT
                    count(DISTINCT a.id) as count
                from (
                    SELECT
                        ca.id
                    from client_accounts ca
                        left join accounts_status_histories ash on ash.client_acount_id = ca.id
                        left join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                        left join recurring_billings rb on rb.client_acount_id = ca.id and rb.updated_at is null
                        left join transactions t on t.client_acount_id = ca.id and t.status_transaction_id in (1,5,8)
                        and not t.type_transaction_id  in (8,14,16,17)
                        and t.modality_transaction_id = @modality_monthly
                        and t.settlement_date >= @first_day_of_month and t.settlement_date < date_add(@last_day_of_month,interval 1 day)
                    where (ca.program_id = id_program or id_program = 0 or id_program is null)
                    AND ca.program_id NOT IN ( @C_PARAGON_PROGRAM )  
                    and ca.migrating = 0 and (date(ca.created_at)< @first_day_of_month or account_paid(ca.id, @first_day_of_month ))
                    and t.id is NULL 
                    and (
                            (
                                (ash.status in (1,8,9,10) and date(ash.created_at) <= @last_day_of_month  )
                                or
                                ( t.id is not null  )
                            )
                            and (ash.updated_at is null or not ash.updated_at <=  @last_day_of_month ) 
                        ) 
                    ) a 
                );    
        END $$

DELIMITER ;



-- Archivo: design_content_request_has_unseen_messages.sql
DELIMITER $$

CREATE FUNCTION `design_content_request_has_unseen_messages`(p_design_content_request_id INT, p_user_id INT) RETURNS tinyint(1)
BEGIN
                DECLARE v_has_unseen_messages BOOLEAN DEFAULT FALSE;
                
                    SET v_has_unseen_messages =
                        EXISTS(
                            SELECT * FROM (SELECT * FROM content_grid_story_flyers WHERE design_request_id = p_design_content_request_id) cgsf
                            JOIN design_material dm ON dm.content_grid_flyer_id = cgsf.id
                            JOIN design_material_conversations dmc ON dmc.design_material_id = dm.id
                            JOIN design_material_messages_seen dmms ON dmms.conversation_id = dmc.id AND dmms.seen_at IS NULL AND dmms.user_id = p_user_id
                            WHERE cgsf.design_request_id = p_design_content_request_id
                        ) OR

                        EXISTS(
                            SELECT * FROM (SELECT * FROM content_grid_carousel WHERE design_request_id = p_design_content_request_id) cgc
                            JOIN design_material dm ON dm.content_grid_carousel_id = cgc.id
                            JOIN design_material_conversations dmc ON dmc.design_material_id = dm.id
                            JOIN design_material_messages_seen dmms ON dmms.conversation_id = dmc.id AND dmms.seen_at IS NULL AND dmms.user_id = p_user_id
                        ) OR

                        EXISTS(
                            SELECT * FROM (SELECT * FROM content_grid_videos WHERE design_request_id = p_design_content_request_id) cgv
                            JOIN design_material dm ON dm.content_grid_video_id = cgv.id
                            JOIN design_material_conversations dmc ON dmc.design_material_id = dm.id
                            JOIN design_material_messages_seen dmms ON dmms.conversation_id = dmc.id AND dmms.seen_at IS NULL AND dmms.user_id = p_user_id
                            WHERE cgv.design_request_id = p_design_content_request_id
                        );

                RETURN v_has_unseen_messages;
            END $$

DELIMITER ;



-- Archivo: employee_cts_calculation.sql
DELIMITER $$

CREATE FUNCTION `employee_cts_calculation`( _employee_user_id INT, _cts_semestral_period ENUM('MAY', 'NOV')) RETURNS decimal(8,2)
BEGIN

    DECLARE _employee_hiring_date DATE;
    DECLARE _employee_id VARCHAR(255) DEFAULT '';

    DECLARE _current_year INT DEFAULT 0;
    DECLARE _previous_year INT DEFAULT 0;
    DECLARE _start_date DATE;
    DECLARE _end_date DATE;

   	DECLARE _total_salary_base DECIMAL(8, 2) DEFAULT 0;

    DECLARE _family_allowance DECIMAL(8, 2) default 0;
    DECLARE _gratification DECIMAL(8,2) default 0;

    DECLARE _results_concatenated VARCHAR(500) DEFAULT '';
    DECLARE _monthly_total DECIMAL(10, 2);
    DECLARE _days_worked DECIMAL(10, 2);
    DECLARE _total_amount_to_be_paid DECIMAL(8, 2) DEFAULT 0;

    
    DECLARE _percentage_to_be_paid_by_semester DECIMAL(5, 2) DEFAULT 0.5;
    DECLARE _six_months_period INT DEFAULT 6;
   	DECLARE _count_months INT default 0;

    SET _current_year = YEAR(NOW());
    SET _previous_year = _current_year - 1;

    
    CASE
        WHEN _cts_semestral_period = 'MAY' THEN
            SET _start_date = CONCAT(_previous_year, '11', '01');
            SET _end_date = CONCAT(_current_year, '11', '30');
        WHEN _cts_semestral_period = 'NOV' THEN
            SET _start_date = CONCAT(_current_year, '10', '01');
            SET _end_date = CONCAT(_current_year, '10', '31');
    END CASE;


    
    SELECT `id`, start_date INTO _employee_id, _employee_hiring_date FROM employees WHERE id_user = _employee_user_id;

   	

   set _family_allowance = (SELECT IFNULL(
	    (SELECT ps.value
		    FROM payment_settings ps
		    JOIN companies c ON c.id = ps.companie_id
		    JOIN employees e ON e.companie_id = ps.companie_id
		    WHERE ps.updated_at IS NULL
		    AND e.id_user = _employee_user_id
		    AND ps.slug = 'FA'
		    AND e.has_family_allowance = 1),0
		 )
	   );

	

	CASE
        WHEN _cts_semestral_period = 'MAY' THEN
			set _gratification = IFNULL((select pde.amount from payroll_payments pp
									join employees e on e.id = pp.employee_id
									join payment_detail_employees pde on pde.payroll_payment_id = pp.id
									where e.id_user = _employee_user_id
									and month(pp.payment_date) = 12
									and year(pp.payment_date) = _previous_year
									and pp.deleted_at is null
									and pde.concept_payment_details_id = 15), 0) / _six_months_period;
        WHEN _cts_semestral_period = 'NOV' THEN
			set _gratification = IFNULL((SELECT pde.amount FROM payroll_payments pp
		                            JOIN employees e ON e.id = pp.employee_id
		                            JOIN payment_detail_employees pde ON pde.payroll_payment_id = pp.id
		                            WHERE e.id_user = _employee_user_id
		                            AND MONTH(pp.payment_date) = 7
		                            AND YEAR(pp.payment_date) = _current_year
		                            and pp.deleted_at is null
		                            AND pde.concept_payment_details_id = 15), 0) / _six_months_period;
    END CASE;

    SELECT start_date INTO _employee_hiring_date FROM employees WHERE id_user = _employee_user_id;


    
    IF( ( _employee_hiring_date BETWEEN _start_date AND _end_date ) AND DAY(_employee_hiring_date) <> 1 AND DAYNAME(_employee_hiring_date) <> 'Sunday' ) then
		SET @salary_base = (select pp.salary
			    					from payroll_payments pp
				    				join employees e on e.id = pp.employee_id
					    			where e.id_user  = _employee_user_id
						    		and month(pp.payment_date) = MONTH(_employee_hiring_date)
						    		and pp.deleted_at is null
						    		and year(pp.payment_date) = YEAR(_employee_hiring_date));
        SET _total_amount_to_be_paid = _total_amount_to_be_paid + @salary_base;

        
        SET _start_date = DATE_ADD( CONCAT( YEAR(_employee_hiring_date), '-', MONTH(_employee_hiring_date), '-', DAY(_start_date) ), INTERVAL 1 MONTH );
       	SET _count_months = _count_months + 1;
    END IF;


   	set @salary_base = JSON_EXTRACT(base_salary_bonification_calculation(_employee_id, MONTH(_start_date), YEAR(_start_date)), '$.base_salary');
	SET _total_amount_to_be_paid = _total_amount_to_be_paid + @salary_base;
	SET _results_concatenated = CONCAT(_results_concatenated, ', ',_start_date,': ', _total_amount_to_be_paid);


   	set _total_salary_base = ((_total_amount_to_be_paid ) * _percentage_to_be_paid_by_semester);
   	SET _results_concatenated = CONCAT('salario: ',_results_concatenated,' | ','bono familiar: ',_family_allowance,'gratificacion: ',_gratification);

    RETURN (_total_salary_base + _family_allowance + _gratification)/2;

  END $$

DELIMITER ;



-- Archivo: employee_expected_workdays.sql
DELIMITER $$

CREATE FUNCTION `employee_expected_workdays`( _employee_user_id INT, _month INT, _year INT, start_date date  ) RETURNS json
BEGIN

        
	
        DECLARE _start_date DATE;
        DECLARE _end_date DATE;
        DECLARE _expected_work_days_count INT DEFAULT 0;
       	DECLARE _is_amg_holiday BOOLEAN DEFAULT FALSE;
       	DECLARE _exists_employee_birth_in_this_month BOOLEAN DEFAULT FALSE;
       	DECLARE _employee_has_valid_justification_for_a_date BOOLEAN DEFAULT FALSE;
        DECLARE _amg_holidays_count INT DEFAULT 0; 
		
        SET _start_date = 	CASE WHEN start_date is null THEN 
        						CONCAT( _year, '-',_month, '-', '01' )
			        	 	ELSE 
			        	 		DATE_FORMAT(start_date, '%Y-%m-%d')
		        			END;
       
        
        
        SET _end_date = LAST_DAY(DATE_FORMAT(CONCAT( _year, '-',_month ,'-' ,'01' ), '%Y-%m-01' ));
        
        WHILE _start_date <= _end_date DO
        	
        	SET _is_amg_holiday = 
        	EXISTS( SELECT * FROM attendance_holidays ah WHERE (( _start_date = CONCAT(ah.`year`, '-', ah.`month`, '-', ah.`day` ) )
			OR ( DATE_FORMAT( _start_date, '%m-%d') = CONCAT(ah.`month`, '-', ah.`day` ) AND ah.`repeat` = 1 )) AND ah.deleted_at IS NULL );

            IF( _is_amg_holiday ) THEN
                SET _amg_holidays_count = _amg_holidays_count + 1;
            ELSE
                IF( DAYOFWEEK( _start_date ) BETWEEN 2 AND 7 ) THEN
                    SET _expected_work_days_count = _expected_work_days_count + 1;
                END IF;
            END IF;

            SET _start_date = DATE_ADD(_start_date, INTERVAL 1 DAY);
        END WHILE;

        SET _exists_employee_birth_in_this_month = EXISTS( SELECT * FROM employees e WHERE e.id_user = _employee_user_id AND MONTH( e.dob ) = _month );
    
        RETURN JSON_OBJECT(
                
       			'expected_work_days', _expected_work_days_count,
                
       			'expected_work_days_including_birthday', IF( _exists_employee_birth_in_this_month, _expected_work_days_count - 1, _expected_work_days_count ), 
                
                'expected_work_days_without_including_holidays_or_birthday', _expected_work_days_count + _amg_holidays_count 
       		   );
        END $$

DELIMITER ;



-- Archivo: employee_statutory_bonus_calculation.sql
DELIMITER $$

CREATE FUNCTION `employee_statutory_bonus_calculation`( _employee_user_id INT, _gratification_semestral_period ENUM('JUL', 'DEC') ) RETURNS decimal(8,2)
BEGIN
            DECLARE _current_year INT DEFAULT 0;
            DECLARE _previous_year INT DEFAULT 0;
            DECLARE _start_date DATE;
            DECLARE _end_date DATE;
            DECLARE _employee_id VARCHAR(255) DEFAULT '';
            DECLARE _company_id INT DEFAULT 0;
            DECLARE _total_salary_base DECIMAL(8, 2) DEFAULT 0;
            DECLARE _total_amount_to_be_paid DECIMAL(8, 2) DEFAULT 0;
            DECLARE _family_allowance DECIMAL(8, 2) default 0;
            DECLARE _days_worked DECIMAL(10, 2);
            
            DECLARE _sixth_month INT DEFAULT 6;
            DECLARE _percentage_to_be_paid_by_semester DECIMAL(5, 2) DEFAULT 0.50;
            DECLARE error_message TEXT DEFAULT 'Error';
            DECLARE _employee_hiring_date DATE;
            DECLARE _count_months INT default 0;
            DECLARE _results_concatenated VARCHAR(500) DEFAULT '';


            
            SELECT companie_id INTO _company_id FROM employees WHERE id = _employee_id;

            IF _company_id IS NULL THEN
                SET error_message = 'Error: Employee doesnt have a company id';
                SIGNAL SQLSTATE '45000' SET message_text = error_message;
            END IF;
        
            SET _current_year = YEAR(NOW());
            SET _previous_year = _current_year - 1;
            
            CASE
                WHEN _gratification_semestral_period = 'JUL' THEN
                    SET _start_date = CONCAT(_current_year, '06', '01');
                    SET _end_date = CONCAT(_current_year, '06', '30');
                WHEN _gratification_semestral_period = 'DEC' THEN
                    SET _start_date = CONCAT(_current_year, '12', '01');
                    SET _end_date = CONCAT(_current_year, '12', '31');
            END CASE;
        
            
            SELECT `id`, start_date INTO _employee_id, _employee_hiring_date FROM employees WHERE id_user = _employee_user_id;

            

            set _family_allowance = (SELECT IFNULL(
                (SELECT ps.value
                    FROM payment_settings ps
                    JOIN companies c ON c.id = ps.companie_id
                    JOIN employees e ON e.companie_id = ps.companie_id
                    WHERE ps.updated_at IS NULL
                    AND e.id_user = _employee_user_id
                    AND ps.slug = 'FA'
                    AND e.has_family_allowance = 1),0
                )
            );
            
          
        
                    
            
            IF( ( _employee_hiring_date BETWEEN _start_date AND _end_date ) AND DAY(_employee_hiring_date) <> 1 AND DAYNAME(_employee_hiring_date) <> 'Sunday' ) then
            SET @salary_base = (select pp.salary
                                            from payroll_payments pp
                                            join employees e on e.id = pp.employee_id
                                            where e.id_user  = _employee_user_id
                                            and month(pp.payment_date) = MONTH(_employee_hiring_date)
                                            and pp.deleted_at is null
                                            and year(pp.payment_date) = YEAR(_employee_hiring_date));
                SET _total_amount_to_be_paid = _total_amount_to_be_paid + @salary_base;
            
                
                SET _start_date = DATE_ADD( CONCAT( YEAR(_employee_hiring_date), '-', MONTH(_employee_hiring_date), '-', DAY(_start_date) ), INTERVAL 1 MONTH );
                SET _count_months = _count_months + 1;
            END IF; 
            
           
           set @salary_base = JSON_EXTRACT(base_salary_bonification_calculation(_employee_id, MONTH(_start_date), YEAR(_start_date)), '$.base_salary');
                    SET _total_amount_to_be_paid = _total_amount_to_be_paid + @salary_base;
                    SET _results_concatenated = CONCAT(_results_concatenated, ', ',_start_date,': ', _total_amount_to_be_paid);
           
           
            
            set _total_salary_base = (((_total_amount_to_be_paid + _family_allowance) * 0.09) + (_total_amount_to_be_paid + _family_allowance)) *_percentage_to_be_paid_by_semester;
           
            
           
                     RETURN  _total_salary_base ;

            
        END $$

DELIMITER ;



-- Archivo: employee_working_days.sql
DELIMITER $$

CREATE FUNCTION `employee_working_days`( _employee_user_id INT, _month INT, _year INT ) RETURNS json
BEGIN
        
        
        DECLARE _exists_employee_birth_in_this_month BOOLEAN DEFAULT FALSE;
        DECLARE _amg_holidays_count INT DEFAULT 0;
        DECLARE _working_days_count INT DEFAULT 0;
        DECLARE _start_date DATE;
        DECLARE _end_date DATE;
        

        
        DECLARE `FAULT` INT DEFAULT 1;
        DECLARE `PERMISSION` INT DEFAULT 2;
        DECLARE LATE INT DEFAULT 3;
        DECLARE MEDICAL_REST INT DEFAULT 4;
        DECLARE VACATIONS INT DEFAULT 5;
        DECLARE REMOTE_WORK INT DEFAULT 6;
        DECLARE OTHER_REASON INT DEFAULT 7;
        DECLARE BIRTHDAY INT DEFAULT 8;

        
        DECLARE APPROVED_BY_MANAGEMENT INT DEFAULT 4;
        DECLARE APPROVED_BY_HUMAN_TALENT INT DEFAULT 6;

        SET _start_date = CONCAT(_year, '-',_month, '-', '01');
        SET _end_date = LAST_DAY(DATE_FORMAT(CONCAT( _year, '-',_month ,'-' ,'01' ), '%Y-%m-01' ));

        SELECT IFNULL(COUNT(*), 0) INTO _amg_holidays_count FROM attendance_holidays WHERE `month` = _month AND `repeat` = 1;
        SET _exists_employee_birth_in_this_month = EXISTS( SELECT * FROM employees e WHERE e.id_user = _employee_user_id AND MONTH(e.dob) = _month );

        SELECT IFNULL(COUNT(*), 0) INTO _working_days_count
        FROM (
            SELECT `date`
                FROM overtime o
                LEFT JOIN justifications j ON j.id = o.id_justification
                WHERE j.deleted_at IS NULL
                    AND o.id_employee = _employee_user_id
                    AND ((type_justification IN (`FAULT`, `PERMISSION`, LATE, REMOTE_WORK, OTHER_REASON) AND o.process_overtime = APPROVED_BY_MANAGEMENT)
                    OR (type_justification IN (MEDICAL_REST, VACATIONS) AND o.process_overtime = APPROVED_BY_HUMAN_TALENT))
                    AND o.`date` BETWEEN _start_date AND _end_date

            UNION

            SELECT DATE(mark_time) AS `date`
                FROM employees_attendance ea
                WHERE ea.user_id = _employee_user_id
                  AND DATE(mark_time) BETWEEN _start_date AND _end_date
                GROUP BY ea.user_id, DATE(mark_time)
        ) valid_working_days_table;
        
        RETURN JSON_OBJECT(
            'working_days_not_including_holidays_or_birthday', _working_days_count, 
            'working_days_including_holidays_and_birthday', _working_days_count + _amg_holidays_count + IF(_exists_employee_birth_in_this_month, 1, 0) 
            );
        END $$

DELIMITER ;



-- Archivo: end_transaction.sql
DELIMITER $$

CREATE FUNCTION `end_transaction`(id_account varchar(36)) RETURNS date
BEGIN
                            declare finish_date date;

                            SET @type_automatic = 1;
                            SET @type_manual = 2;
                            SET @type_others = 6;
                            SET @type_return_charge = 15;
                            
                            select settlement_date into finish_date
                                from transactions t
                                where (t.type_transaction_id in (@type_automatic,@type_manual,@type_others) or 
                                        (t.type_transaction_id = @type_return_charge and t.modality_transaction_id in(6,7)))
                                and t.status_transaction_id in (1,5,8) and client_acount_id = id_account
                                order by settlement_date desc limit 1;
                                
                        RETURN finish_date;
                    END $$

DELIMITER ;



-- Archivo: fifth_category_calculation.sql
DELIMITER $$

CREATE FUNCTION `fifth_category_calculation`(_employee_id varchar(150), _month int, _year int) RETURNS json
BEGIN
        DECLARE salary DECIMAL(10, 2) DEFAULT 0;
        DECLARE _start_date DATE;
        DECLARE _start_month INT DEFAULT 1;
       	DECLARE _last_month INT DEFAULT 12;
        DECLARE _months_work INT DEFAULT 12;
        DECLARE _salary_total_year decimal(10,2);
       	DECLARE _salary_total_base_year decimal(10,2);
        DECLARE _rent decimal(10,2) DEFAULT 0;
        DECLARE _computable decimal(10,2) default 0;

       	DECLARE _previous_salary decimal(10,2);
       	DECLARE _previous_salary_base decimal(10,2);
       	DECLARE _new_salary decimal(10,2);
       	DECLARE _new_salary_base decimal(10,2);
       	DECLARE _hours_worked int;
       	DECLARE _working_hours int;
       	DECLARE user_id int;
       	DECLARE _first_salary decimal(10,2);
       	DECLARE _first_salary_base decimal(10,2);
       	DECLARE _month_before date;
      	DECLARE _month_new date;
      	DECLARE _record_count int;
       	DECLARE _gratification_julio decimal(10,2) default 0;
        DECLARE _gratification_diciembre decimal(10,2) default 0;
        DECLARE _company_id INT DEFAULT 0;
       	DECLARE _past_rent decimal(10,2);

    	DECLARE i INT DEFAULT 1;
    	DECLARE numNombres INT;
    	DECLARE nombreActual VARCHAR(100);
    	DECLARE mesActual VARCHAR(100);

   		DECLARE j INT DEFAULT 1;
    	DECLARE numNombresFifth INT;
    	DECLARE p_tramos_fifth VARCHAR(100);
    	DECLARE p_limite_fifth decimal(10,2);
        DECLARE p_monto_fifth decimal(10,2);
        DECLARE p_resultado_fifth decimal(10,2);
        DECLARE rent_total decimal(10,2) default 0;
        DECLARE soft_pay decimal(10,2) default 0;
 DECLARE me_falta_pagar decimal(10,2) default 0;
 DECLARE me_falta_pagar_cuotas decimal(10,2) default 0;



       DECLARE v_employee_detail_final json;

	   DECLARE v_fifth_category_details_final  json;

	   DECLARE v_aporte_details_final  json;


       DROP TEMPORARY TABLE IF EXISTS tem_consider_salary;
       CREATE TEMPORARY TABLE tem_consider_salary(p_id int, p_salary decimal(10,2), p_month int,p_employee_id char(36),p_name varchar(255));

       DROP TEMPORARY TABLE IF EXISTS tem_fifth_details;
       CREATE TEMPORARY TABLE tem_fifth_details(p_id int, p_tramos  varchar(255), p_limite decimal(10,2),p_monto decimal(10,2),p_resultado decimal(10,2));

       DROP TEMPORARY TABLE IF EXISTS tem_aportes_details;
       CREATE TEMPORARY TABLE tem_aportes_details(p_id int, p_amount decimal(10,2),p_name varchar(255));


    	SET numNombres = 19; -- El número total de nombres en tu lista

   	   WHILE i <= numNombres DO
        CASE i
            WHEN 1 THEN
                SET nombreActual = 'ENERO';
                SET mesActual = 1;
            WHEN 2 THEN
                SET nombreActual = 'FEBRERO';
                SET mesActual = 2;
            WHEN 3 THEN
                SET nombreActual = 'MARZO';
                SET mesActual = 3;
            WHEN 4 THEN
                SET nombreActual = 'ABRIL';
                SET mesActual = 4;
            WHEN 5 THEN
                SET nombreActual = 'MAYO';
                SET mesActual = 5;
            WHEN 6 THEN
                SET nombreActual = 'JUNIO';
                SET mesActual = 6;
            WHEN 7 THEN
                SET nombreActual = 'JULIO';
                SET mesActual = 7;
            WHEN 8 THEN
                SET nombreActual = 'GRATIFICACIÓN JULIO';
                SET mesActual = NULL;
            WHEN 9 THEN
                SET nombreActual = 'AGOSTO';
                SET mesActual = 8;
            WHEN 10 THEN
                SET nombreActual = 'SEPTIEMBRE';
                SET mesActual = 9;
            WHEN 11 THEN
                SET nombreActual = 'OCTUBRE';
                SET mesActual = 10;
            WHEN 12 THEN
                SET nombreActual = 'NOVIEMBRE';
                SET mesActual = 11;
            WHEN 13 THEN
                SET nombreActual = 'DICIEMBRE';
                SET mesActual = 12;
            WHEN 14 THEN
                SET nombreActual = 'GRATIFICACIÓN DICIEMBRE';
                SET mesActual = NULL;
            WHEN 15 THEN
                SET nombreActual = 'BONIF. EXTRAOR. 9 % GRATIFICACIONES';
                SET mesActual = NULL;
            WHEN 16 THEN
                SET nombreActual = 'OTROS INGRESOS (RH, HORAS EXTR.)';
                SET mesActual = NULL;
            WHEN 17 THEN
                SET nombreActual = 'INGRESOS POR AÑO';
                SET mesActual = NULL;
            WHEN 18 THEN
                SET nombreActual = 'DEDUCCION 7 UIT';
                SET mesActual = NULL;

            WHEN 19 THEN
                SET nombreActual = 'COMPUTABLE';
                SET mesActual = NULL;
        END CASE;

        INSERT INTO tem_consider_salary (p_id,p_salary, p_month, p_employee_id, p_name)
        VALUES (i,0, mesActual, _employee_id, nombreActual);

        SET i = i + 1;
    END WHILE;

--      Obtener los valores de las escalas
		SET @percentage_1_categoria = (SELECT percentage FROM fifth_category_scales WHERE name = '1er Tramo' AND updated_at IS NULL)/100;
		SET @percentage_2_categoria = (SELECT percentage FROM fifth_category_scales WHERE name = '2do Tramo' AND updated_at IS NULL)/100;
		SET @percentage_3_categoria = (SELECT percentage FROM fifth_category_scales WHERE name = '3er Tramo' AND updated_at IS NULL)/100;
		SET @percentage_4_categoria = (SELECT percentage FROM fifth_category_scales WHERE name = '4to Tramo' AND updated_at IS NULL)/100;
		SET @percentage_5_categoria = (SELECT percentage FROM fifth_category_scales WHERE name = '5to Tramo' AND updated_at IS NULL)/100;

        SET @limit_1_categoria = (SELECT `limit` FROM fifth_category_scales WHERE name = '1er Tramo' AND updated_at IS NULL);
        SET @limit_2_categoria = (SELECT `limit` FROM fifth_category_scales WHERE name = '2do Tramo' AND updated_at IS NULL);
        SET @limit_3_categoria = (SELECT `limit` FROM fifth_category_scales WHERE name = '3er Tramo' AND updated_at IS NULL);
        SET @limit_4_categoria = (SELECT `limit` FROM fifth_category_scales WHERE name = '4to Tramo' AND updated_at IS NULL);
        SET @limit_5_categoria = (SELECT `limit` FROM fifth_category_scales WHERE name = '5to Tramo' AND updated_at IS NULL);

-- 		obtener el valor de la uit
        SET @uit = (SELECT ps.value from payment_settings ps where slug='UIT' and ps.updated_at is null);

--      obtener el user_id del empleado
       	SET user_id = (select e.id_user  from employees e join users u on u.id=e.id_user WHERE e.id  = _employee_id);


	SET numNombresFifth = 5; -- El número total de nombres en tu lista

    	WHILE j <= numNombresFifth DO
        CASE j
            WHEN 1 THEN
                SET p_tramos_fifth = concat('HASTA ',@limit_1_categoria,' UIT','         ',ROUND(@percentage_1_categoria * 100),'%');
                SET p_limite_fifth =CAST( (@uit*@limit_1_categoria) AS DECIMAL(10,2));
                SET p_monto_fifth =0;
                SET p_resultado_fifth =0;
            WHEN 2 THEN
                SET p_tramos_fifth = concat('DE ',@limit_1_categoria, ' A ',@limit_2_categoria, ' UIT','      ',ROUND(@percentage_2_categoria * 100),'%');
                SET p_limite_fifth = CAST( (@uit*@limit_2_categoria) AS DECIMAL(10,2));
                SET p_monto_fifth =0;
                SET p_resultado_fifth =0;
            WHEN 3 THEN
                SET p_tramos_fifth = concat('DE ',@limit_2_categoria, ' A ',@limit_3_categoria, ' UIT','    ',ROUND(@percentage_3_categoria * 100),'%');
                SET p_limite_fifth =CAST( (@uit*@limit_3_categoria) AS DECIMAL(10,2));
                SET p_monto_fifth =0;
                SET p_resultado_fifth =0;
            WHEN 4 THEN
                SET p_tramos_fifth = concat('DE ',@limit_3_categoria, ' A ',@limit_4_categoria, ' UIT','    ',ROUND(@percentage_4_categoria * 100),'%');
                SET p_limite_fifth = CAST( (@uit*@limit_4_categoria) AS DECIMAL(10,2));
                SET p_monto_fifth =0;
                SET p_resultado_fifth =0;
            WHEN 5 THEN
                SET p_tramos_fifth = concat('DE ',@limit_4_categoria, ' A MAS');
                SET p_limite_fifth =0 ;
                SET p_monto_fifth =0;
                SET p_resultado_fifth =0;

        END CASE;

        INSERT INTO tem_fifth_details (p_id,p_tramos, p_limite, p_monto, p_resultado)
        VALUES (j,p_tramos_fifth, p_limite_fifth, p_monto_fifth, p_resultado_fifth);

        SET j = j + 1;
    END WHILE;



--      GRATIFICACION VALORES



        IF ( (select grati_period_julio from companies c WHERE c.id =_company_id )=1 ) then
       	SET _gratification_julio = (select employee_statutory_bonus_calculation(user_id, 'JUL'));
	    UPDATE tem_consider_salary  set p_salary = _gratification_julio where p_name='GRATIFICACIÓN JULIO';

        END IF;

        IF ( (select grati_period_dic from companies c WHERE c.id =_company_id )=1 ) then

        SET _gratification_diciembre = (select employee_statutory_bonus_calculation(user_id, 'DEC'));
        UPDATE tem_consider_salary  set p_salary = _gratification_diciembre where p_name='GRATIFICACIÓN DICIEMBRE';

		END IF;


--      obtener el dia que el empleado empezo a trabajar
        SELECT start_date INTO _start_date FROM employees WHERE id = _employee_id;



		SET @sum_of_salaries = 0 ;
	    SET @sum_of_salary_base = 0;



		WHILE _start_month <= _last_month DO
		-- Llamar a la función get_employee_salary y almacenar el resultado en una variable

		SET @salary = get_employee_salary(_employee_id,_start_month,_year);
	   	SET @salary_base = JSON_EXTRACT(base_salary_bonification_calculation(_employee_id,_start_month,_year), '$.base_salary');

    	-- Sumar los salarios
		SET @sum_of_salaries = @sum_of_salaries + @salary;
		SET @sum_of_salary_base = @sum_of_salary_base + @salary_base;

    	-- Tabla temporal para insertar salario por meses
		update tem_consider_salary  set p_salary = @salary where p_month=_start_month;

        -- Incrementar el contador del mes
		SET _start_month = _start_month + 1;

		END WHILE;

	    SET _salary_total_year = @sum_of_salaries + _gratification_julio + _gratification_diciembre;


--      calcular la renta de 5ta categoria si el salario anual es mayor a 7 uit
        if(_salary_total_year>(7*@uit)) then

-- 	   		Diferencia del salario anual y las 7uit
        	set _computable=_salary_total_year-(7*@uit);
-- 	   		1er Tramo
	   		if(_computable>0) THEN
	   			set _rent =(if(_computable>@limit_1_categoria*@uit,@limit_1_categoria*@uit,_computable))*(@percentage_1_categoria);

	   		    update tem_fifth_details  set p_monto =  _computable,p_resultado=_rent where p_id=1;
			end if;
-- 			2do Tramo
			if(_computable-(@limit_1_categoria*@uit)>0) then
				set _rent = _rent + if((_computable-(@limit_1_categoria*@uit)>(@limit_2_categoria*@uit)),(@limit_2_categoria*@uit),(_computable-(@limit_1_categoria)*@uit))*(@percentage_2_categoria);

			 update tem_fifth_details  set p_monto =  (_computable-(@limit_1_categoria)*@uit),p_resultado=if((_computable-(@limit_1_categoria*@uit)>(@limit_2_categoria*@uit)),(@limit_2_categoria*@uit),(_computable-(@limit_1_categoria)*@uit))*(@percentage_2_categoria)  where p_id=2;

			end if;
-- 			3er Tramo
			if(_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)>0) THEN
	   			set _rent = _rent + if((_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)>(@limit_3_categoria*@uit)),(@limit_3_categoria*@uit),(_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)))*(@percentage_3_categoria);
				 update tem_fifth_details  set p_monto =  (_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)),p_resultado=if((_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)>(@limit_3_categoria*@uit)),(@limit_3_categoria*@uit),(_computable-(@limit_1_categoria*@uit)-(@limit_2_categoria*@uit)))*(@percentage_3_categoria) where p_id=3;
	   		end if;
-- 			4to Tramo
		    if (_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) > 0) then
	        	set _rent = _rent + if ((_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) > (@limit_4_categoria * @uit)), (@limit_4_categoria * @uit), (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit)) * (@percentage_4_categoria);
		      update tem_fifth_details  set p_monto =   (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit),p_resultado=if ((_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) > (@limit_4_categoria * @uit)), (@limit_4_categoria * @uit), (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit)) * (@percentage_4_categoria) where p_id=4;
	        end if;
-- 		   	5to Tramo
		    if (_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit) > 0) then
		        set _rent = _rent + if ((_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit) > (@limit_5_categoria * @uit)), (@limit_5_categoria * @uit), (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit)) * (@percentage_5_categoria);
		     update tem_fifth_details  set p_monto =   (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit),p_resultado=if ((_computable - (@limit_1_categoria * @uit) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit) > (@limit_5_categoria * @uit)), (@limit_5_categoria * @uit), (_computable - (@limit_1_categoria * @uit)) - (@limit_2_categoria * @uit) - (@limit_3_categoria * @uit) - (@limit_4_categoria * @uit)) * (@percentage_5_categoria) where p_id=5;
		       end if;
-- 		   	dividir entre los meses de trabajo + gratificacion


--          payroll suma+

		    set rent_total= IFNULL(_rent,0) ;





		    set soft_pay = (select sum(IFNULL(pde.amount,0)) amount  from payroll_payments pp join payment_detail_employees pde on pp.id =pde.payroll_payment_id  and pde.concept_payment_details_id =10
	  		WHERE pp.employee_id =_employee_id
	   		and pp.file_approved_route is not null and year(pp.payment_date)=_year and  month(pp.payment_date)<_month);

            select YEAR(start_date), MONTH(start_date) - 1 into @year_init, @month_init from employees where id = _employee_id;

		    set _past_rent= (select IFNULL(sum(IFNULL(amount,0)),0) from contributions_fifth_category cfc 
            WHERE cfc.employee_id= _employee_id and cfc.deleted_at is null and year(cfc.date_contribution)=_year);

		    IF (soft_pay is null) then set soft_pay =0; END IF;
		    IF (_past_rent is null) then set _past_rent =0; END IF;

            set @month_divide = 12 - _month + 1;

			set me_falta_pagar = rent_total - ( _past_rent + soft_pay);

		    set me_falta_pagar_cuotas = me_falta_pagar/@month_divide;


			END IF;

	  		set @ingresos_por_ano= (select sum(p_salary) from tem_consider_salary where p_id not in(17,18,19));
	  		set @deduccion_uit =(-@uit)*7;
	   		set @computable =@ingresos_por_ano+@deduccion_uit;


	     update tem_consider_salary  set p_salary = @ingresos_por_ano where p_name='INGRESOS POR AÑO';
	     update tem_consider_salary  set p_salary = @deduccion_uit where p_name='DEDUCCION 7 UIT';
	     update tem_consider_salary  set p_salary = @computable where p_name='COMPUTABLE';

	    -- data final

	    set @sum_aporte_final=(  select IFNULL(sum(IFNULL(amount,0)),0) from contributions_fifth_category cfc WHERE cfc.employee_id =_employee_id and cfc.deleted_at is null);

	    set v_employee_detail_final = ((select  JSON_ARRAYAGG(JSON_OBJECT('p_salary',tcs.p_salary,'p_date',tcs.p_month,'p_form_date',monthname(concat('2023','-',tcs.p_month,'-','01') ),'name',tcs.p_name))  from tem_consider_salary tcs));

	    set v_fifth_category_details_final=(select  JSON_ARRAYAGG(JSON_OBJECT('p_tramos',tfd.p_tramos,'p_limite',tfd.p_limite,'p_monto',p_monto,'p_resultado',p_resultado ))  from tem_fifth_details tfd);

	    set v_aporte_details_final =(SELECT JSON_ARRAYAGG(JSON_OBJECT('p_month',  CASE months.monthname
           			       WHEN 'January' THEN 'Enero' WHEN 'February' THEN 'Febrero' WHEN 'March' THEN 'Marzo' WHEN 'April' THEN 'Abril' WHEN 'May' THEN 'Mayo' WHEN 'June' THEN 'Junio'
           			 WHEN 'July' THEN 'Julio' ELSE months.monthname END, 'p_amount', IFNULL(cfc.amount, 0))
					) FROM (SELECT 'January' AS monthname UNION SELECT 'February' UNION SELECT 'March' UNION SELECT 'April' UNION SELECT 'May' UNION SELECT 'June'
   					UNION SELECT 'July' ) AS months LEFT JOIN contributions_fifth_category cfc on months.monthname = MONTHNAME(cfc.date_contribution) AND cfc.employee_id = _employee_id
    				AND cfc.deleted_at IS NULL  );


	   RETURN JSON_OBJECT('prueba',@month_divide,
	                      '_rent',ifnull(CAST(if(me_falta_pagar_cuotas<=0,0,me_falta_pagar_cuotas)  AS DECIMAL(10,2)),0.00),
           				  'employee_detail',v_employee_detail_final,
					      'p_uit',@uit,
					      'fifth_category_details',v_fifth_category_details_final,
					      'total',rent_total,
					      'aporte_por_mes',ifnull(CAST(if(me_falta_pagar_cuotas<=0,0,me_falta_pagar_cuotas)  AS DECIMAL(10,2)),0.00),
				          '_computable',_computable,
				          'employee_id',_employee_id,
				          'aportes_details', v_aporte_details_final,
				          'sum_aporte', @sum_aporte_final,
				          'total_aportes',rent_total- @sum_aporte_final,
				          '_gratification_diciembre',_gratification_diciembre,
				          '_gratification_julio',_gratification_julio,
				          '_first_salary',_first_salary,
				          'soft_pay',soft_pay,
				          '_salary_total_year',_salary_total_year,
                          'me_falta_pagar_cuotas', me_falta_pagar_cuotas,
				          'me_falta_pagar', me_falta_pagar,
				          'rent_total', rent_total,
				          '_past_rent', _past_rent,
				          'soft_pay', soft_pay,
				          '@month_divide', @month_divide

    				);
 DROP TEMPORARY TABLE IF EXISTS tem_fifth_details;
           		   DROP TEMPORARY TABLE IF EXISTS tem_consider_salary;
           		         DROP TEMPORARY TABLE IF EXISTS tem_aportes_details;

END $$

DELIMITER ;



-- Archivo: fn_get_count_on_pending_or_done_sales.sql
DELIMITER $$

CREATE FUNCTION `fn_get_count_on_pending_or_done_sales`(
			p_status_sale ENUM( 'PENDING', 'DONE' ),
			p_program_id INT,
			p_day INT,
			p_month INT,
			p_year INT,
			p_seller_id INT
        ) RETURNS json
BEGIN
            DECLARE C_ADD_SERVICE INT DEFAULT 1;
            DECLARE C_CHANGE_SERVICE INT DEFAULT 2;

            DECLARE C_SALE_IN_PENDING INT DEFAULT 1;
            DECLARE C_SALE_IN_UNDERVIEW INT DEFAULT 2;
            DECLARE C_SALE_APPROVED INT DEFAULT 4;

		    
            DECLARE v_daily_count_new_sales INT DEFAULT 0;
            DECLARE v_daily_count_sales_from_add INT DEFAULT 0;
            DECLARE v_daily_count_sales_from_change INT DEFAULT 0;
            DECLARE v_daily_fee_amount DECIMAL(16, 2) DEFAULT 0.00;
            DECLARE v_daily_ip_amount DECIMAL(16, 2) DEFAULT 0.00;
           
            
            DECLARE v_monthly_count_new_sales INT DEFAULT 0;
            DECLARE v_monthly_count_sales_from_add INT DEFAULT 0;
            DECLARE v_monthly_count_sales_from_change INT DEFAULT 0;
            DECLARE v_monthly_fee_amount DECIMAL(16, 2) DEFAULT 0.00;
            DECLARE v_monthly_ip_amount DECIMAL(16, 2) DEFAULT 0.00;

            SELECT
            	
                IFNULL( SUM( IF( ps.id IS NULL AND DAY( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_day, 1, 0 ) ), 0 ), 
                IFNULL( SUM( IF( ps.`type` = C_ADD_SERVICE AND DAY( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_day, 1, 0 ) ), 0 ),
                IFNULL( SUM( IF( ps.`type` = C_CHANGE_SERVICE AND DAY( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_day, 1, 0 ) ), 0 ),
                SUM(
                	IF(
                		DAY( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_day,
                		IFNULL( s.fee_amount, 0 ),
                		0  
                	)
                ), 
                SUM(
                	IF(
                		DAY( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_day,
                		IFNULL( ip.amount, 0 ), 0
                	)
                ),
                
                
                IFNULL( SUM( IF( ps.id IS NULL AND MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_month, 1, 0 ) ), 0 ), 
                IFNULL( SUM( IF( ps.`type` = C_ADD_SERVICE AND MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_month, 1, 0 ) ), 0 ),
                IFNULL( SUM( IF( ps.`type` = C_CHANGE_SERVICE AND MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_month, 1, 0 ) ), 0 ),
                SUM(
                	IF(
                		MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_month,  
                		IFNULL( s.fee_amount, 0 ),
                		0
                	)
                ), 
                SUM(
                	IF(
                		MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) ) = p_month,
                		IFNULL( ip.amount, 0 ),
                		0
                	)
                )
            INTO
            	
                v_daily_count_new_sales,
                v_daily_count_sales_from_add,
                v_daily_count_sales_from_change,
                v_daily_fee_amount,
                v_daily_ip_amount,
                
                
                v_monthly_count_new_sales,
                v_monthly_count_sales_from_add,
                v_monthly_count_sales_from_change,
                v_monthly_fee_amount,
                v_monthly_ip_amount
            FROM sales s
            LEFT JOIN events ev ON ev.id = s.event_id
            LEFT JOIN program_sales ps ON ps.sale_id = s.id
            LEFT JOIN initial_payments ip ON s.id = ip.sale_id
            WHERE ( 
                    p_status_sale IS NULL OR 
                    ( p_status_sale = 'DONE' AND s.status_id = C_SALE_APPROVED ) OR 
                    ( p_status_sale = 'PENDING' AND s.status_id IN (C_SALE_IN_PENDING, C_SALE_IN_UNDERVIEW) )
                )   
                AND ( p_program_id IS NULL OR ( s.program_id = p_program_id ) )
                AND ( p_seller_id IS NULL OR ( ev.user_id = p_seller_id ) )
                AND ( p_month IS NULL OR ( MONTH( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) )  = p_month ) )
                AND ( p_year IS NULL OR ( YEAR( IF( p_status_sale = 'PENDING', s.created_at, s.updated_at ) )  = p_year ) );
            
            RETURN JSON_OBJECT(
            	'status_type', p_status_sale,
            	'daily_sales', IFNULL( v_daily_count_new_sales, 0.00 ) + IFNULL( v_daily_count_sales_from_add , 0.00 ) + IFNULL( v_daily_count_sales_from_change, 0.00 ),
                'daily_sales_new', IFNULL( v_daily_count_new_sales, 0.00 ),
                'daily_sales_from_add', IFNULL( v_daily_count_sales_from_add , 0.00 ),
                'daily_sales_from_change', IFNULL( v_daily_count_sales_from_change, 0.00 ),
                'daily_sales_fee_amount', IFNULL( v_daily_fee_amount, 0.00 ),
                'daily_sales_ip_amount', IFNULL( v_daily_ip_amount, 0.00 ),
                
                'monthly_sales', IFNULL( v_monthly_count_new_sales, 0.00 ) + IFNULL( v_monthly_count_sales_from_add , 0.00 ) + IFNULL( v_monthly_count_sales_from_change, 0.00 ),
                'monthly_sales_new', IFNULL( v_monthly_count_new_sales, 0.00 ),
                'monthly_sales_from_add', IFNULL( v_monthly_count_sales_from_add , 0.00 ),
                'monthly_sales_from_change', IFNULL( v_monthly_count_sales_from_change, 0.00 ),
                'monthly_sales_fee_amount', IFNULL( v_monthly_fee_amount, 0.00 ),
                'monthly_sales_ip_amount', IFNULL( v_monthly_ip_amount, 0.00 )
            );
        END $$

DELIMITER ;



-- Archivo: fn_get_data_of_event.sql
DELIMITER $$

CREATE FUNCTION `fn_get_data_of_event`(_client_account_id varchar(36), _date_event date) RETURNS json
begin
            declare cc_negotiations_completed int;
            declare cc_rejected_offers int;
            declare cc_approved_offers int;
            declare cc_verifications_start int;
            declare cc_verifications_end int;
            declare cc_verifications_realtor_start int;
            declare cc_verifications_realtor_end int;
            declare cc_workplans int;
            declare cc_removed_accounts int;
            declare cc_no_balance_accounts int;
            declare _client_id varchar(36);
               declare _event_id int;
            declare sum_events_happened int;
               declare json_events json;
           
          
            
            
            select count(dopot.id) into cc_negotiations_completed
            from ds_offer_payment_orders_tracking dopot 
            join ds_offer_payment_orders dopo on dopot.offer_payment_order_id = dopo.offer_payment_order_id 
            join offer o on dopo.offer_id = o.id
            where dopot.payment_order_status_id = 6
            and o.client_account = _client_account_id
            and date(dopot.created_at) = _date_event;
        
            
            select count(ot.id) into cc_rejected_offers
            from offer_tracking ot 
            join offer o on ot.offer_id = o.id 
            where o.status = 2 and
            o.client_account = _client_account_id and date(ot.created_at) = _date_event;
        
            
            select count(ot.id) into cc_approved_offers
            from offer_tracking ot 
            join offer o on ot.offer_id = o.id 
            where ot.status = 3 and
            ot.process = 3 and
            o.client_account = _client_account_id and date(ot.created_at) = _date_event;
        
        
            
            select count(nl.id) into cc_verifications_start
            from ncr_letters nl 
            where nl.account_client_id = _client_account_id 
            and date(nl.created_at) = _date_event;
        
            
            select count(tn.id) into cc_verifications_end
            from tracking_ncrs tn 
            join ncr_letters nl on tn.ncr_id = nl.id 
            where tn.status_id = 6 and nl.account_client_id = _client_account_id and date(tn.created_at) = _date_event;
        
            
            SELECT count(nr.id) into cc_verifications_realtor_start
            FROM ncr_realtor nr 
            where nr.account_client_id = _client_account_id 
            and date(nr.created_at) = _date_event;
        
            
            SELECT count(nr.id) into cc_verifications_realtor_end
            FROM ncr_realtor nr 
            where nr.account_client_id = _client_account_id 
            and date(nr.date_completed) = _date_event;
        
            
            select count(wp.id) into cc_workplans
            from work_plans wp 
            where wp.client_account_id = _client_account_id and date(wp.created_at) = _date_event;
        
            
        
            SELECT client_id into _client_id from client_accounts ca where ca.id = _client_account_id;
            SELECT event_id into _event_id from sales s where s.client_id =  _client_id 
            and s.program_id = 4 and s.status_id = 4 and s.annul =0 and s.annulled_at is null;
                  
            select count(tda.id) into cc_removed_accounts
            from ds_list_credits dlc 
            inner join sales s 
            on (dlc.client_id = _client_id or dlc.event_id = _event_id) 
            and s.program_id = 4 and s.status_id =4 and s.program_id = 4 
            and s.annul =0 and s.annulled_at is null
            join tracking_ds_account tda on 
            tda.`action` = 'Account Phase' 
            and `after` = 'Removed (R) ' 
            and dlc.id = tda.creditor_id
            where dlc.client_id 
            and date(tda.created_at) = _date_event;
        
            
            select count(tda.id) into cc_no_balance_accounts
            from ds_list_credits dlc 
            inner join sales s 
            on (dlc.client_id = _client_id or dlc.event_id = _event_id) 
            and s.program_id = 4 and s.status_id =4 and s.program_id = 4 
            and s.annul =0 and s.annulled_at is null
            join tracking_ds_account tda on 
            tda.`action` = 'Account Phase' 
            and `after` = 'No Balance (Nb)'
            and dlc.id = tda.creditor_id
            where dlc.client_id  
            and date(tda.created_at) = _date_event;
        
            set sum_events_happened = cc_negotiations_completed + cc_negotiations_completed + cc_approved_offers + cc_verifications_start +
            cc_verifications_end + cc_workplans + cc_removed_accounts + cc_no_balance_accounts;
        
            
        
            if (sum_events_happened = 0) then
                return '[]';
            else
                   SELECT JSON_ARRAYAGG(
                       JSON_OBJECT('text', _text, 'id', id)
                   ) as events into json_events
                   from (
                   select (if(cc_negotiations_completed = 0,'' ,
                   CONCAT(cc_negotiations_completed, ' negotation', if(cc_negotiations_completed = 1,'','s') ,' completed '))) _text, 1 id
                   UNION
                   select (if(cc_rejected_offers = 0, '', 
                   CONCAT(cc_rejected_offers, ' rejected offer', if(cc_rejected_offers = 1,'','s') ))) _text, 2 id
                   UNION
                   select (if(cc_approved_offers = 0, '', 
                   CONCAT(cc_approved_offers, ' approved offer', if(cc_approved_offers = 1,'','s')))) _text, 3 id
                   UNION
                   select (if(cc_verifications_start = 0, '', 
                   CONCAT(cc_verifications_start, ' verification', if(cc_verifications_start = 1,'','s') ,' created '))) _text, 4 id
                   UNION
                   select (if(cc_verifications_end = 0, '', 
                   CONCAT(cc_verifications_end, ' verification', if(cc_verifications_end = 1,'','s') ,' finalized '))) _text, 5 id
                   UNION
                   select (if(cc_verifications_realtor_start = 0, '', 
                   CONCAT(cc_verifications_realtor_start, 'realtor verification', if(cc_verifications_realtor_start = 1,'','s') ,' finalized '))) _text, 6 id
                   UNION
                select (if(cc_verifications_realtor_end = 0, '', 
                   CONCAT(cc_verifications_realtor_end, ' realtor verification', if(cc_verifications_realtor_end = 1,'','s') ,' finalized '))) _text, 7 id
                   UNION
                   select (if(cc_workplans = 0, '', 
                   CONCAT(cc_workplans, ' workplan', if(cc_workplans = 1,'','s') ,' created '))) _text, 8 id
                   UNION
                   select (if(cc_removed_accounts = 0, '', 
                   CONCAT(cc_removed_accounts, ' account', if(cc_removed_accounts = 1,'','s') ,' removed '))) _text, 9 id
                   UNION
                   select (if(cc_no_balance_accounts = 0, '', 
                CONCAT(cc_no_balance_accounts, ' account', if(cc_no_balance_accounts = 1,'','s') ,' with no balance '))) _text, 10 id) tb_events;
               
               return json_events;
            end if;
            
        END $$

DELIMITER ;



-- Archivo: fn_get_last_message.sql
DELIMITER $$

CREATE FUNCTION `fn_get_last_message`(
	        p_ticket_customer_id int
        ) RETURNS json
BEGIN
            
            DECLARE last_message JSON;

            
            SELECT JSON_OBJECT(
                'ticket', ctc.ticket_customer_id,
                'message_id', ctc.id,
                'message', ctc.message,
                'created_by', ctc.created_by,
                'created_at', ctc.created_at,
                'employee', CONCAT_WS(' ',u.first_name,u.last_name),
                'type', mtct.name,
                'type_id', mtct.id
            ) INTO last_message
            FROM chat_ticket_customer ctc
            JOIN message_ticket_customer_type mtct on mtct.id = ctc.message_customer_type_id
            left JOIN
                users u on u.id = ctc.created_by
            where
                ctc.ticket_customer_id = p_ticket_customer_id
            AND ctc.message_customer_type_id not in(6,7)
            ORDER BY ctc.created_at DESC
            LIMIT 1;

            RETURN last_message;
        END $$

DELIMITER ;



-- Archivo: fn_get_last_message_not_viewed.sql
DELIMITER $$

CREATE FUNCTION `fn_get_last_message_not_viewed`(
	        p_ticket_customer_id int,
	        p_current_user_id int 
        ) RETURNS int
BEGIN
	
            DECLARE last_message_id int;

        
            DROP TEMPORARY TABLE IF EXISTS temp_message_not_viewed; 
            CREATE TEMPORARY TABLE temp_message_not_viewed AS
            SELECT 
                subquery.ticket,
                subquery.id_user,
                subquery.message_id,
                subquery.message,
                subquery.not_viewed,
                subquery.created_by,
                subquery.created_at
            FROM (
            SELECT DISTINCT
                    tc.id AS ticket, 
                    ctcv.id_user, 
                    ctc.id AS message_id,
                    ctc.created_by,
                    ctc.message,
                    ctc.created_at,
                    CASE 
                        WHEN ctcv.chat_ticket_customer_id IS NULL or ctcv.id_user != p_current_user_id THEN 1
                        ELSE 0
                    END AS not_viewed
                FROM 
                    ticket_customer tc
                JOIN 
                    participants_ticket_customer ptc ON ptc.ticket_customer_id = tc.id AND ptc.id_user = p_current_user_id
                JOIN 
                    chat_ticket_customer ctc ON ctc.ticket_customer_id = tc.id and ctc.message<>'Roger Segura has changed the status of the ticket to In Progress'
                LEFT JOIN 
                    chat_ticket_customer_view ctcv 
                    ON ctcv.chat_ticket_customer_id = ctc.id  AND ctcv.id_user = p_current_user_id
                WHERE tc.id = p_ticket_customer_id
            ) AS subquery
            WHERE subquery.id_user != p_current_user_id OR subquery.not_viewed = 1       
            AND (
                CASE 
                    WHEN subquery.created_by = p_current_user_id THEN subquery.created_by <> p_current_user_id
                    ELSE TRUE
                END
            );

        
            select tmnv.message_id into last_message_id from temp_message_not_viewed tmnv order by tmnv.created_at asc limit 1;

            return last_message_id;
        END $$

DELIMITER ;



-- Archivo: fn_get_messages_pending.sql
DELIMITER $$

CREATE FUNCTION `fn_get_messages_pending`(
            p_current_user_id int,
	        p_ticket_customer_id int
        ) RETURNS int
BEGIN
	
            DECLARE v_pending_messages int;

        
            DROP TEMPORARY TABLE IF EXISTS temp_message_not_viewed; 
            CREATE TEMPORARY TABLE temp_message_not_viewed AS
            SELECT 
                subquery.ticket,
                subquery.id_user,
                subquery.message_id,
                subquery.message,
                subquery.not_viewed,
                subquery.created_by
            FROM (
            SELECT DISTINCT
                    tc.id AS ticket, 
                    ctcv.id_user, 
                    ctc.id AS message_id,
                    ctc.created_by,
                    ctc.message,
                    CASE 
                        WHEN ctcv.chat_ticket_customer_id IS NULL or ctcv.id_user != p_current_user_id THEN 1
                        ELSE 0
                    END AS not_viewed
                FROM 
                    ticket_customer tc
                JOIN participants_ticket_customer ptc ON ptc.ticket_customer_id = tc.id AND ptc.id_user = p_current_user_id
                JOIN 
                    chat_ticket_customer ctc ON ctc.ticket_customer_id = tc.id 
                    and ctc.message<>'Roger Segura has changed the status of the ticket to In Progress'
                    and ctc.message_customer_type_id not in (6,7)
                
                LEFT JOIN 
                    chat_ticket_customer_view ctcv 
                    ON ctcv.chat_ticket_customer_id = ctc.id  AND ctcv.id_user = p_current_user_id
                WHERE tc.id = p_ticket_customer_id 
                AND ((SELECT count(id) FROM chat_ticket_customer_tags ctct WHERE ctct.id_user = p_current_user_id AND ctct.chat_ticket_customer_id = ctc.id) = 1
                     OR NOT EXISTS(SELECT id FROM chat_ticket_customer_tags ctct WHERE ctct.chat_ticket_customer_id = ctc.id))
            ) AS subquery
            WHERE subquery.id_user != p_current_user_id OR subquery.not_viewed = 1       
            AND (
                CASE 
                    WHEN subquery.created_by = p_current_user_id THEN subquery.created_by <> p_current_user_id
                    ELSE TRUE
                END
            );

        
            select count(tmnv.ticket) into v_pending_messages from temp_message_not_viewed tmnv;

            return v_pending_messages;
        END $$

DELIMITER ;



-- Archivo: fn_get_monthly_payments_excluding_active_clients.sql
DELIMITER $$

CREATE FUNCTION `fn_get_monthly_payments_excluding_active_clients`(
            p_date DATE,
            p_program_id INT
        ) RETURNS int
BEGIN
            
            DECLARE v_total INT DEFAULT 0;	
            
            
            SET @MONTHLY := 1;

            
            SET @APPROVED := 1;
            SET @SETTLED_SUCCESSFULLY := 5;
            SET @CAPTURED_PENDING_SETTLEMENT := 8;
        
            
            SET @INITIAL_PAYMENT := 3;
            SET @CREDIT := 8;
            SET @VOID := 10;
            SET @REFUND := 11;
            SET @ZERO_PAYMENT := 14;
            SET @CHARGE_BACK := 15;
            SET @PARCIAL_VOID := 16;
            SET @PARCIAL_REFUND := 17;

            
            SET @OUTSTANDING := 7;
            SET @O_HOLD := 2;
            SET @O_CANCELED := 4;
            SET @O_CLOSED := 6;
        
            SET @LOYAL := 5;
            SET @L_IN_PROGRESS := 11;
            SET @L_POTENTIAL := 12;
            SET @L_STAND_BY := 13;

            SET @ACTIVE := 1;
            SET @A_CURRENT := 8;
            SET @A_ONE_MONTH_LATE := 9;
            SET @A_TWO_MONTHS_LATE := 10;
        
            
            SET @ACTIVE_RANGE := 1;
        
            
            SET @START_OF_MONTH := DATE_FORMAT(p_date, '%Y-%m-01');
            SET @SIXTH_DAY_OF_MONTH := DATE_FORMAT(p_date, '%Y-%m-06');	

            DROP TEMPORARY TABLE IF EXISTS tmp_status_histories;
            CREATE TEMPORARY TABLE IF NOT EXISTS tmp_status_histories
            SELECT 
                ca.id `client_account_id`,
                ash.status,
                ash.created_at,
                ash.updated_at,
                pd.deployment_start_date,
                ca.program_id,
                ca.account
            FROM accounts_status_histories ash
            JOIN client_accounts ca ON ca.id = ash.client_acount_id
            JOIN (
                SELECT 
                    p.id,
                    CASE 
                        WHEN pdd.deployment_date IS NOT NULL AND pdd.deployment_date <= @START_OF_MONTH 
                        THEN @START_OF_MONTH
                        ELSE @SIXTH_DAY_OF_MONTH
                    END `deployment_start_date`
                FROM programs p
                LEFT JOIN program_deployment_dates pdd ON p.id = pdd.program_id AND pdd.new_range = @ACTIVE_RANGE
            ) pd ON pd.id = ca.program_id
            WHERE ash.created_at < DATE_ADD(pd.deployment_start_date, INTERVAL 1 MONTH)
            AND ash.created_at = (
                SELECT MAX(ash2.created_at)
                FROM accounts_status_histories ash2
                WHERE ash2.client_acount_id = ash.client_acount_id
                AND ash2.created_at < DATE_ADD(pd.deployment_start_date, INTERVAL 1 MONTH)
            )
            AND ash.status NOT IN (@A_CURRENT, @A_ONE_MONTH_LATE, @A_TWO_MONTHS_LATE);
        
            
            SELECT
                COUNT(DISTINCT ca.id)
                INTO v_total
            FROM client_accounts ca
            JOIN (
                SELECT 
                    p.id,
                    CASE 
                        WHEN pdd.deployment_date IS NOT NULL AND pdd.deployment_date <= @START_OF_MONTH 
                        THEN @START_OF_MONTH
                        ELSE @SIXTH_DAY_OF_MONTH
                    END `deployment_start_date`
                FROM programs p
                LEFT JOIN program_deployment_dates pdd ON p.id = pdd.program_id AND pdd.new_range = @ACTIVE_RANGE
            ) pd ON pd.id = ca.program_id
            
            JOIN tmp_status_histories ash ON ash.client_account_id = ca.id
            JOIN transactions t ON t.client_acount_id = ca.id 
                AND t.modality_transaction_id = @MONTHLY
                AND t.status_transaction_id IN (@APPROVED, @SETTLED_SUCCESSFULLY, @CAPTURED_PENDING_SETTLEMENT)
                AND t.type_transaction_id NOT IN (@INITIAL_PAYMENT, @CREDIT, @VOID, @REFUND, @ZERO_PAYMENT, @CHARGE_BACK, @PARCIAL_VOID, @PARCIAL_REFUND)
                AND t.settlement_date >= pd.deployment_start_date
                AND t.settlement_date < DATE_ADD(pd.deployment_start_date, INTERVAL 1 MONTH)
            WHERE DATE(ca.created_at) < pd.deployment_start_date
            AND ca.migrating = 0
            AND (p_program_id IS NULL OR ca.program_id = p_program_id)
            AND (
                (ash.status IN (@OUTSTANDING, @O_HOLD, @O_CANCELED, @O_CLOSED) AND DATE(ash.created_at) < DATE_ADD(pd.deployment_start_date, INTERVAL 1 MONTH))
                OR 
                (ash.status IN (@LOYAL, @L_IN_PROGRESS, @L_POTENTIAL, @L_STAND_BY) AND DATE(ash.created_at) < pd.deployment_start_date)
            )
            AND (ash.updated_at IS NULL OR ash.updated_at < DATE_ADD(pd.deployment_start_date, INTERVAL 1 MONTH));
            
        RETURN v_total;
        END $$

DELIMITER ;



-- Archivo: fn_last_day_client.sql
DELIMITER $$

CREATE FUNCTION `fn_last_day_client`(_client_account_id varchar(36)) RETURNS date
BEGIN
        declare months_left int;
           	declare available_balance decimal(16,2);
            declare _monthly_amount decimal(16,2);
            declare _total_debit decimal(16,2);
            declare total_money_client_has_to_pay decimal(16,2);
            declare maximum_balance decimal(16,2);
            declare _sale_id int;
           	declare _contract_fee_client_months int;
            declare _client_created_at datetime;
            declare _client_ends_at datetime;
 
			
            select ifnull(dca.available_balance,0), ifnull(dca.total_debit_initial, 0) 
            into available_balance, _total_debit
            from ds_clients_ad dca
            join client_accounts ca on dca.client_id = ca.client_id
            where ca.id = _client_account_id;
           
            
            set maximum_balance = _total_debit * 0.8;
           
            
            SELECT rb.monthly_amount into _monthly_amount from recurring_billings rb 
            where rb.client_acount_id = _client_account_id and rb.updated_at is null
            limit 1;
           
           
            set total_money_client_has_to_pay = maximum_balance - available_balance;
                    
           
           if (available_balance < maximum_balance) THEN
            
            
            set months_left = CEIL(total_money_client_has_to_pay /if(_monthly_amount=0, 1, _monthly_amount));
           	if (months_left > 9999) then
           		return DATE_ADD(curdate(), interval 9999 month);
           	else
            	return DATE_ADD(curdate(), interval months_left month);
            end if;
           
           else
            select ce.date_event into _client_ends_at
            from client_events ce where ce.client_event_type_id = 12 
            and ce.client_account_id = _client_account_id;
           
            if (_client_ends_at is null) then
	            select s.id, ca.created_at into _sale_id, _client_created_at
				from client_accounts ca 
				left join sales s on ca.client_id = s.client_id  
				and s.status_id =4 and s.program_id = 4
				where ca.program_id = 4
				and ca.id = _client_account_id
				limit 1;
			
				select cf.months into _contract_fee_client_months
				from contract_fees cf where cf.sale_id = _sale_id;
			
				if (_sale_id is null) then
					return DATE_ADD(curdate(), interval 9999 month);
				else
					if (_contract_fee_client_months > 9999) then
	           			return DATE_ADD(DATE(_client_created_at), interval 9999 month);
		           	else
		            	return DATE_ADD(DATE(_client_created_at), interval _contract_fee_client_months month);
		            end if;
				end if;
			else
				return date(_client_ends_at);
			end if;
		   end if;
        END $$

DELIMITER ;



-- Archivo: fn_payment_type_id_to_commission_id.sql
DELIMITER $$

CREATE FUNCTION `fn_payment_type_id_to_commission_id`(payment_type_id int) RETURNS int
BEGIN
            declare commission_type_id int;
           	declare commission_manual_id int;
           
            SELECT csct.id into commission_manual_id FROM ced_setting_commission_type csct where csct.slug = 'manu-reco';
            select case 
                        when payment_type_id = 1  then 6
                        when payment_type_id = 4  then 7
                        when payment_type_id = 5  then 8
                        when payment_type_id = 6  then 9
                        when payment_type_id = 2  then commission_manual_id
                        end into commission_type_id;
            
        RETURN commission_type_id;
        END $$

DELIMITER ;



-- Archivo: fn_validate_ci_tab.sql
DELIMITER $$

CREATE FUNCTION `fn_validate_ci_tab`(next_step_id int, sent_status varchar(50), service_type varchar(50), status varchar(50)) RETURNS int
BEGIN
            set @tab = 0;
            CASE
            WHEN (next_step_id IN (2, 3, 4, 6, 7, 101, 102, 104) and ((sent_status = 'SENT' or service_type = 'INVESTIGATION') and status = 'REVISION') = false) THEN
                    set @tab = 1;
            WHEN status = 'DONE' THEN
                    set @tab = 2;
            WHEN ((sent_status = 'SENT' or service_type = 'INVESTIGATION') and status = 'REVISION') THEN
                    set @tab = 3;
                ELSE 
                    set @tab = 0;
            END CASE;
            return @tab;
            END $$

DELIMITER ;



-- Archivo: generate_sale_commission_ce.sql
DELIMITER $$

CREATE FUNCTION `generate_sale_commission_ce`(
                        id_program int,
                        id_sale int,
                        senior int,
                        fee decimal(16,2),
                        id_capture int,
                        id_seller int,
                        id_event int,
                        country_seller int,
                        amount_suggested decimal(16,2),
                        from_connection int
            ) RETURNS int
BEGIN
                        declare country_seller int;
                        declare commissions_seller decimal(16,2);
                        declare captured_amount decimal(16,2);
                        declare sale_amount_PE decimal(16,2);
                        declare sale_amount_US decimal(16,2);
                        declare PE_percent decimal(16,2);
                        declare US_percent decimal(16,2);
                        declare id_commission int;
                        declare id_sup int;
                        declare id_role int;
                        declare id_sup_department int;
                        declare id_assist_sup_department int;
                        declare sale_module int;
                        declare id_change int default 0;
                        declare percentage_commission_for_sup decimal(16,2) default 0;
                        declare percentage_commission_for_assist_sup decimal(16,2) default 0;
                        declare amount_commission_for_sup decimal(16,2) default 0;
                        declare amount_commission_for_assist_sup decimal(16,2) default 0;
                        declare last_id_sales_commissions int default 0;
                        declare commission_for_sup_capture decimal(16,2);
                        declare commission_for_sup_sale decimal(16,2);
            
                         if(id_program = 1)then

                            select id into @id_rate from rate_sales where sale_id = id_sale limit 1;
                            if(@id_rate is not null)then
                                   
                                    select case
				                        when senior = 1 then seller_PE_bg
				                        when senior = 2 then seller_PE_jr
				                        when senior = 3 then seller_PE_sr
				                        when senior = 4 then seller_PE_mr
				                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
				                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
				                	from commissions c
				                    inner join rate_sales rs on rs.rate_id=c.rate_id
				                	where sale_id = id_sale and program_id = id_program;
                            else
					                select fee_amount into @fee from sales where id = id_sale;
					                case
					                    when(@fee < 900)then
					                        set @rate_id = 86;
					                    when(@fee >= 900 and @fee <= 2199)then
					                       set @rate_id = 87;
					                    when(@fee > 2199 and @fee <= 3599)then
					                       set @rate_id = 88;
					                    when (@fee > 3599)then
					                        set @rate_id = 89;
					                end case;
					                select case
					                        when senior = 1 then seller_PE_bg
					                        when senior = 2 then seller_PE_jr
					                        when senior = 3 then seller_PE_sr
					                        when senior = 4 then seller_PE_mr
					                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
					                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
					                from commissions c
					                    where c.rate_id = @rate_id;
                            end if;
            
                        if(id_commission in (7, 8))then
            
			                case
			                    when(fee < 999)then
			
			                        set id_commission =  7;
			
			                    when(fee >= 999 and fee <= 1500)then
			
			                        set id_commission =  8;
			
			                    when(fee > 1500 and fee <= 2000)then
			
			                        set id_commission =  32;
			
			                    when (fee > 2000)then
			
			                        set id_commission =  33;
			
			                end case;
            
            
            
                        elseif(id_commission in (29, 30))then
			                case
			                    when(fee < 2000)then
			
			                        set id_commission = 29;
			
			                    when(fee >= 2000 and fee <= 3000)then
			
			                        set id_commission = 30;
			
			                    when(fee > 3000)then
			
			                        set id_commission = 31;
			
			                    end case;
                        end if;

                                   select case
				                    when senior = 1 then seller_PE_bg
				                    when senior = 2 then seller_PE_jr
				                    when senior = 3 then seller_PE_sr
				                    when senior = 4 then seller_PE_mr
				                end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
				                into sale_amount_PE, sale_amount_US, captured_amount
				            from commissions c
				            where c.id = id_commission;
            
                    elseif(id_program = 2)then
                       
                    select amount_captured,case
                                        when senior = 1 then seller_PE_bg
                                        when senior = 2 then seller_PE_jr
                                        when senior = 3 then seller_PE_sr
                                        when senior = 4 then seller_PE_mr
                                        else seller_PE_bg
	                end ,if(senior = 3,seller_US_sr,seller_US_jr)
	                    into captured_amount,sale_amount_PE,sale_amount_US
	                from commissions c
	                where program_id = id_program and `description` like concat('%',fee,'%');
            
                    elseif(id_program = 3)then
            
		                if(fee > 0 and fee <= 1500)then
		                    set id_commission = 13;
		                elseif(fee > 1500 and fee <= 3000)then
		                    set id_commission = 27;
		                elseif(fee > 3000)then
		                    set id_commission = 28;
		                end if;
		
		                 select case
		                        when senior = 1 then seller_PE_bg
		                        when senior = 2 then seller_PE_jr
		                        when senior = 3 then seller_PE_sr
		                        when senior = 4 then seller_PE_mr
                                else seller_PE_bg
		                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
		                    into sale_amount_PE, sale_amount_US, captured_amount
		                from commissions c
		                where c.id = id_commission; 
            
                    elseif(id_program = 4 or id_program = 8) THEN
            
		                select amount_captured,case
		                                        when senior = 1 then seller_PE_bg
		                                        when senior = 2 then seller_PE_jr
		                                        when senior = 3 then seller_PE_sr
		                                        when senior = 4 then seller_PE_mr
                                                else seller_PE_bg
		                end ,if(senior = 3,seller_US_sr,seller_US_jr)
		                    into captured_amount,sale_amount_PE,sale_amount_US
		                from commissions c
		                where program_id = id_program;
            
                    elseif(id_program = 5)then   
            
		            	if(fee <= 500)then
		
		            		set id_commission = 15;
		
		            	elseif(fee > 500 and fee <= 1000) then
		
		            		set id_commission = 38;
		
		            	elseif(fee > 1000)then
		
		            		set id_commission = 39;
		
		            	end if;
		
		
		                select case
		                        when senior = 1 then seller_PE_bg
		                        when senior = 2 then seller_PE_jr
		                        when senior = 3 then seller_PE_sr
		                        when senior = 4 then seller_PE_mr
                                else seller_PE_bg
		                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
		                    into sale_amount_PE, sale_amount_US, captured_amount
		                from commissions c
		                where c.id = id_commission;
            
            
                    elseif(id_program = 6)then
            
                        if(fee <= 400)then
            
                            set id_commission = 34;
            
                        elseif(fee > 400)then
            
                            set id_commission = 16;
            
                        end if;
            
		                select case
		                        when senior = 1 then seller_PE_bg
		                        when senior = 2 then seller_PE_jr
		                        when senior = 3 then seller_PE_sr
		                        when senior = 4 then seller_PE_mr
                                else seller_PE_bg
		                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
		                    into sale_amount_PE, sale_amount_US, captured_amount
		                from commissions c
		                where c.id = id_commission;
            
                    elseif(id_program = 7)then
            
                        if(fee <= 400)then
            
                            set id_commission = 35;
            
                        elseif(fee > 400)then
            
                            set id_commission = 17;
            
                        end if;
            
		                select case
		                        when senior = 1 then seller_PE_bg
		                        when senior = 2 then seller_PE_jr
		                        when senior = 3 then seller_PE_sr
		                        when senior = 4 then seller_PE_mr
                                else seller_PE_bg
		                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
		                    into sale_amount_PE, sale_amount_US, captured_amount
		                from commissions c
		                where c.id = id_commission;
            
                    elseif(id_program = 9)then
		                select case
		                        when senior = 1 then seller_PE_bg
		                        when senior = 2 then seller_PE_jr
		                        when senior = 3 then seller_PE_sr
		                        when senior = 4 then seller_PE_mr
                                else seller_PE_bg
		                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
		                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
		                from commissions c
		                    inner join rate_sales rs on rs.rate_id=c.rate_id
		                where sale_id = id_sale and program_id = id_program;
            
                    else
            
                        set captured_amount = 0;
                        set sale_amount_PE = 0;
                        set sale_amount_US = 0;
                    end if;
            
                        IF (fee > 0) THEN
                            
                            select module_id into sale_module from sales where id = id_sale;
                           
                           
                            select u.id into id_sup
                            from users u
                            join user_module um on um.user_id = u.id
                            where um.module_id = 2
                            and um.role_id = 2 
                            and u.status = 1
                            limit 1;
            
                               
                            select u.id into id_sup_department
                            from users u
                            join user_module um on um.user_id = u.id
                            where um.module_id = if(from_connection = 1, 20,sale_module)
                            and um.role_id = 2
                            and u.status = 1
                            limit 1;
                           
                            
                            select u.id into id_assist_sup_department
                            from users u
                            join user_module um on um.user_id = u.id
                            where um.module_id = if(from_connection = 1, 20,sale_module)
                            and um.role_id = 14
                            and u.status = 1
                            limit 1;
                           
                           
                           
                           
                           SELECT value into percentage_commission_for_sup FROM ced_settings_commission_roles cscr WHERE module_id = sale_module and role_id = 2 limit 1;
                          
                           
                           SELECT value into percentage_commission_for_assist_sup FROM ced_settings_commission_roles cscr WHERE module_id = sale_module and role_id = 14 limit 1;
                           
                           SELECT um.role_id INTO id_role FROM user_module um WHERE um.user_id = id_capture LIMIT 1;
                            
                            if((id_capture <> 1 and id_seller <> 1) and (id_capture <> id_sup and id_seller <> id_sup))then
                                if(id_capture = id_seller)then
                                    set id_change = 1;
                                    set captured_amount = 0;
                                end if;
                            end if;
                           
                            
                            
                            
                            IF (id_capture = id_sup_department or id_capture = id_assist_sup_department or id_role in (1, 17, 2)) THEN
                                set amount_commission_for_sup = 0;
                                set amount_commission_for_assist_sup = 0;
                            ELSE
                                set commission_for_sup_capture = captured_amount;
                                            
                                IF (commission_for_sup_capture is null) then
                                    set commission_for_sup_capture = 0;
                                END IF;
            
                                set amount_commission_for_sup = commission_for_sup_capture*(percentage_commission_for_sup/100) * (id_sup_department is not null);
                                set amount_commission_for_assist_sup = commission_for_sup_capture*(percentage_commission_for_assist_sup/100) * 
                               (id_assist_sup_department is not null);
                            END IF;
                           
                            set id_role = null;
            
                            INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`,amount_for_sup,type_for,amount_for_assist_sup)
                            VALUES (id_sale,id_capture,captured_amount,1,id_change, amount_commission_for_sup, 2, amount_commission_for_assist_sup);
                           
                            set last_id_sales_commissions = @@identity;
                            
                           	IF (id_sup_department IS NOT NULL) THEN
	                            INSERT INTO general_commissions_supervisors
	                            (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
	                            VALUES(amount_commission_for_sup, id_sup_department, last_id_sales_commissions, 2, 1, NOW(),2, sale_module);
                           	END IF;
                        	
                           	IF (id_assist_sup_department IS NOT NULL) THEN
	                            INSERT INTO general_commissions_supervisors
	                            (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
	                            VALUES(amount_commission_for_assist_sup, id_assist_sup_department, last_id_sales_commissions, 2, 1, NOW(),2, sale_module);
	                        END IF;
                           
            
                        
                            
                            set commissions_seller = sale_amount_PE;
            
                            if (country_seller = 2) then
                                set commissions_seller=sale_amount_US;
                            end if;
                            
                           
                            SELECT um.role_id INTO id_role FROM user_module um WHERE um.user_id = id_seller LIMIT 1;
                            
                           
                            IF (id_seller = id_sup_department or id_seller = id_assist_sup_department or id_role in (1, 17, 2)) THEN
                                set amount_commission_for_sup = 0;
                                set amount_commission_for_assist_sup = 0;
                            ELSE
                                set commission_for_sup_sale = commissions_seller;
                               
                                if (commission_for_sup_sale is null ) then
                                    set commission_for_sup_sale = 0;
                                end if;
                                
                                set amount_commission_for_sup = commission_for_sup_sale*(percentage_commission_for_sup/100)* (id_sup_department is not null);
                                set amount_commission_for_assist_sup = commission_for_sup_sale*(percentage_commission_for_assist_sup/100)*
                                (id_assist_sup_department is not null);
            
                            END IF;
            
                            INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`, amount_for_sup, type_for,amount_for_assist_sup)
                            VALUES (id_sale,id_seller,commissions_seller,2,0, amount_commission_for_sup, 2, amount_commission_for_assist_sup);
                            
                            set last_id_sales_commissions = @@identity;
                           
                           
                           	IF (id_sup_department IS NOT NULL) THEN                           
	                            INSERT INTO general_commissions_supervisors
	                            (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
	                            VALUES(amount_commission_for_sup, id_sup_department, last_id_sales_commissions, 2, 2, NOW(),2, sale_module);
	                        END IF;
                    
                        	IF (id_assist_sup_department IS NOT NULL) THEN
                            INSERT INTO general_commissions_supervisors
                            (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
                            VALUES(amount_commission_for_assist_sup, id_assist_sup_department, last_id_sales_commissions, 2, 2, NOW(), 2, sale_module); 
							END IF;                            
            
                            
                            
                        END IF;
            
                    RETURN 1;
                    END $$

DELIMITER ;



-- Archivo: generate_sale_commission_crm.sql
DELIMITER $$

CREATE FUNCTION `generate_sale_commission_crm`(
            id_program int,
            id_sale int,
            senior int,
            fee decimal(16,2),
            id_capture int,
            id_seller int,
            id_event int,
            country_seller int,
            amount_suggested decimal(16,2),
            id_lead int) RETURNS int
begin
            declare country_seller int;
            declare commissions_seller decimal(16,2);
            declare captured_amount decimal(16,2);
            declare sale_amount_PE decimal(16,2);
            declare sale_amount_US decimal(16,2);
            declare PE_percent decimal(16,2);
            declare US_percent decimal(16,2);
            declare id_commission int;
            declare id_sup int;
            declare id_chief int;
            declare id_change int default 0;
            declare commission_for_sup_capture decimal(16,2);
            declare commission_for_sup_sale decimal(16,2);
            declare percentage_commission_for_sup decimal(16,2) default 0;
            declare amount_commission_for_sup decimal(16,2) default 0;
            declare last_id_sales_commissions int default 0;
            declare type_commission_sale int default 1;
            declare type_commission_capture int default 1;
            declare exists_id int;
            declare exists_id2 int;
            declare is_ceo_capture tinyint;
            declare is_ceo_seller tinyint;
            declare percentage_for_ceo decimal(16,2);
            declare amount_commission_for_ceo decimal(16,2) default 0;

            if(id_program = 1)then
            select id into @id_rate from rate_sales where sale_id = id_sale limit 1;
            if(@id_rate is not null)then
                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
                from commissions c
                    inner join rate_sales rs on rs.rate_id=c.rate_id
                where sale_id = id_sale and program_id = id_program;
            else
                select fee_amount into @fee from sales where id = id_sale;
                case
                    when(@fee < 900)then
                        set @rate_id = 86;
                    when(@fee >= 900 and @fee <= 2199)then
                    set @rate_id = 87;
                    when(@fee > 2199 and @fee <= 3599)then
                    set @rate_id = 88;
                    when (@fee > 3599)then
                        set @rate_id = 89;
                end case;
                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
                from commissions c
                    where c.rate_id = @rate_id;
            end if;


            if(id_commission in (7, 8))then

                case
                    when(fee < 999)then

                        set id_commission =  7;

                    when(fee >= 999 and fee <= 1500)then

                        set id_commission =  8;

                    when(fee > 1500 and fee <= 2000)then

                        set id_commission =  32;

                    when (fee > 2000)then

                        set id_commission =  33;

                end case;

            elseif(id_commission in (29, 30))then

                case
                    when(fee < 2000)then

                        set id_commission = 29;

                    when(fee >= 2000 and fee <= 3000)then

                        set id_commission = 30;

                    when(fee > 3000)then

                        set id_commission = 31;

                    end case;
            end if;

            select case
                    when senior = 1 then seller_PE_bg
                    when senior = 2 then seller_PE_jr
                    when senior = 3 then seller_PE_sr
                    when senior = 4 then seller_PE_mr
                end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
                into sale_amount_PE, sale_amount_US, captured_amount
            from commissions c
            where c.id = id_commission;

            elseif(id_program = 2)then

                select amount_captured,case
                                        when senior = 1 then seller_PE_bg
                                        when senior = 2 then seller_PE_jr
                                        when senior = 3 then seller_PE_sr
                                        when senior = 4 then seller_PE_mr
                end ,if(senior = 3,seller_US_sr,seller_US_jr)
                    into captured_amount,sale_amount_PE,sale_amount_US
                from commissions c
                where program_id = id_program and `description` like concat('%',fee,'%');

            elseif(id_program = 3) then

                if(fee > 0 and fee <= 1500)then
                    set id_commission = 13;
                elseif(fee > 1500 and fee <= 3000)then
                    set id_commission = 27;
                elseif(fee > 3000)then
                    set id_commission = 28;
                end if;

                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
                    into sale_amount_PE, sale_amount_US, captured_amount
                from commissions c
                where c.id = id_commission;


            elseif(id_program = 4  or id_program = 8) then

                select amount_captured,case
                                        when senior = 1 then seller_PE_bg
                                        when senior = 2 then seller_PE_jr
                                        when senior = 3 then seller_PE_sr
                                        when senior = 4 then seller_PE_mr
                end ,if(senior = 3,seller_US_sr,seller_US_jr)
                    into captured_amount,sale_amount_PE,sale_amount_US
                from commissions c
                where program_id = id_program;

            elseif(id_program = 5)then

                if(fee <= 500)then

                    set id_commission = 15;

                elseif(fee > 500 and fee <= 1000) then

                    set id_commission = 38;

                elseif(fee > 1000)then

                    set id_commission = 39;

                end if;


                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
                    into sale_amount_PE, sale_amount_US, captured_amount
                from commissions c
                where c.id = id_commission;


            elseif(id_program = 6)then

                if(fee <= 400)then

                    set id_commission = 34;

                elseif(fee > 400)then

                    set id_commission = 16;

                end if;

                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
                    into sale_amount_PE, sale_amount_US, captured_amount
                from commissions c
                where c.id = id_commission;

            elseif(id_program = 7)then

                if(fee <= 400)then

                    set id_commission = 35;

                elseif(fee > 400)then

                    set id_commission = 17;

                end if;

                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured
                    into sale_amount_PE, sale_amount_US, captured_amount
                from commissions c
                where c.id = id_commission;

            elseif(id_program = 9)then
                select case
                        when senior = 1 then seller_PE_bg
                        when senior = 2 then seller_PE_jr
                        when senior = 3 then seller_PE_sr
                        when senior = 4 then seller_PE_mr
                    end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
                    into sale_amount_PE, sale_amount_US, captured_amount, id_commission
                from commissions c
                    inner join rate_sales rs on rs.rate_id=c.rate_id
                where sale_id = id_sale and program_id = id_program;
            else
                set captured_amount = 0;
                set sale_amount_PE = 0;
                set sale_amount_US = 0;

            end if;

            IF (fee > 0) THEN
            
            SELECT value into percentage_for_ceo FROM ced_settings_commission_roles cscr WHERE cscr.role_id = 1;
            set percentage_for_ceo = percentage_for_ceo / 100;

            SELECT (role_id = 1) INTO is_ceo_seller from user_module um where um.user_id = id_seller LIMIT 1;

            
            select u.id into id_sup
            from users u
            inner join user_module um on um.user_id = u.id
            where um.module_id = 2
            and um.role_id = 2;

            SELECT um.user_id into id_chief
            FROM user_module um
            WHERE um.module_id = 2 AND um.role_id = 17;


            
                if(id_capture <> 1 and id_seller <> 1)then
                
                    if(id_capture = id_seller)then
                    
                        set id_change = 1;
                        set id_capture = id_sup;
                    
                        set captured_amount = 0;
                    
                        update events set created_users = id_capture where id = id_event;

                    end if;
                end if;


            

            IF (id_seller <> id_sup and is_ceo_seller = 0) THEN 
                    
                    SELECT u.id INTO exists_id FROM users u
                    inner join user_module um on um.user_id = u.id
                    where
                    um.module_id = 2
                    and um.main_module = 1
                    and um.role_id in (3,5,13)
                    and um.user_id = id_seller;

                    IF (exists_id IS NOT NULL) THEN
                        set type_commission_sale = 2;
                    END IF;

                    
                    select u.id INTO exists_id2 from users u
                    inner join user_module um on um.user_id = u.id and um.main_module is null
                    where
                    um.module_id = 2
                    and um.role_id in (3,5,13)
                    and um.user_id = id_seller;

                    IF (exists_id2 IS NOT NULL) THEN
                        set type_commission_sale = 1;
                    END IF;
            ELSE
                    set type_commission_sale = 2; 
            END IF;

            SET exists_id = NULL;
            SET exists_id2 = NULL;

            SELECT (role_id = 1) INTO is_ceo_capture from user_module um where um.user_id = id_capture LIMIT 1;

            IF (id_capture <> id_sup and is_ceo_capture = 0) THEN 
                    
                    SELECT u.id INTO exists_id FROM users u
                    inner join user_module um on um.user_id = u.id
                    where
                    um.module_id = 2
                    and um.main_module = 1
                    and um.role_id in (3,5,13)
                    and um.user_id = id_capture;

                    IF (exists_id IS NOT NULL) THEN
                        set type_commission_capture = 2;
                    END IF;

                    
                    select u.id INTO exists_id2 from users u
                    inner join user_module um on um.user_id = u.id and (um.main_module is null or um.main_module = 0)
                    where
                    um.module_id = 2
                    and um.role_id in (3,5,13)
                    and um.user_id = id_capture;

                    IF (exists_id2 IS NOT NULL) THEN
                        set type_commission_capture = 1;
                    END IF;
            ELSE
                    set type_commission_capture = 2; 
            END IF;



            
                SELECT value into percentage_commission_for_sup FROM ced_settings_commission_roles cscr WHERE module_id = 2 and role_id = 2;

                


                
                
                
                IF (id_capture = id_sup OR id_capture = id_chief OR is_ceo_capture = 1) THEN
                    set amount_commission_for_sup = 0;
                ELSE
                    set commission_for_sup_capture = captured_amount;

                    IF (commission_for_sup_capture is null) then
                        set commission_for_sup_capture = 0;
                    END IF;

                    set amount_commission_for_sup = commission_for_sup_capture * (percentage_commission_for_sup/100);
                    set amount_commission_for_ceo = commission_for_sup_capture * percentage_for_ceo;
                END IF;

                INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`,amount_for_sup,type_for,amount_for_ceo)
                VALUES (id_sale, id_capture, captured_amount, 1, id_change, amount_commission_for_sup, type_commission_capture, amount_commission_for_ceo);

                set last_id_sales_commissions = @@identity;

                INSERT INTO general_commissions_supervisors
                (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
                VALUES(amount_commission_for_sup, id_sup, last_id_sales_commissions, type_commission_capture, 1, NOW(),2, 2);
                



                
                set commissions_seller = sale_amount_PE;

                if (country_seller = 2) then
                    set commissions_seller = sale_amount_US;
                end if;
                


                

                IF (id_seller = id_sup OR id_seller = id_chief OR is_ceo_seller = 1) THEN
                    set amount_commission_for_sup = 0;
                ELSE
                    set commission_for_sup_sale = commissions_seller;

                    if (commission_for_sup_sale is null ) then
                        set commission_for_sup_sale = 0;
                    end if;

                    set amount_commission_for_sup = commission_for_sup_sale*(percentage_commission_for_sup/100);
                    set amount_commission_for_ceo = commission_for_sup_sale * percentage_for_ceo;
                END IF;

                INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`, amount_for_sup, type_for, amount_for_ceo)
                VALUES (id_sale,id_seller,commissions_seller,2,0,amount_commission_for_sup, type_commission_sale, amount_commission_for_ceo);

                set last_id_sales_commissions = @@identity;

                INSERT INTO general_commissions_supervisors
                (amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
                VALUES(amount_commission_for_sup, id_sup, last_id_sales_commissions, type_commission_sale, 2, NOW(), 2, 2); 
                

            END IF;

            RETURN 1;
        END $$

DELIMITER ;



-- Archivo: generate_sale_commission_programs.sql
DELIMITER $$

CREATE FUNCTION `generate_sale_commission_programs`(
            id_program int,
            id_sale int,
            senior int,
            fee decimal(16,2),
            id_capture int,
            id_seller int,
            id_event int,
            country_seller int,
            amount_suggested decimal(16,2)) RETURNS int
begin
            declare country_seller int;
            declare commissions_seller decimal(16,2);
            declare captured_amount decimal(16,2);
            declare sale_amount_PE decimal(16,2);
            declare sale_amount_US decimal(16,2);
            declare PE_percent decimal(16,2);
            declare US_percent decimal(16,2);
            declare id_commission int;
            declare id_sup int;
            declare id_sup_department int;
            declare sale_module int;
            declare id_change int default 0;
            declare percentage_commission_for_sup decimal(16,2) default 0;
            declare amount_commission_for_sup decimal(16,2) default 0;
            declare last_id_sales_commissions int default 0;
            declare commission_for_sup_capture decimal(16,2);
            declare commission_for_sup_sale decimal(16,2);

         	if(id_program = 1)then

				select id into @id_rate from rate_sales where sale_id = id_sale limit 1;
                if(@id_rate is not null)then
						select seller_PE_bg, seller_PE_bg, amount_captured, c.id
							into sale_amount_PE, sale_amount_US, captured_amount, id_commission
						from commissions c
							inner join rate_sales rs on rs.rate_id=c.rate_id
						where sale_id = id_sale and program_id = id_program;
                else
                    select fee_amount into @fee from sales where id = id_sale;
                    case
                        when(@fee < 900)then
                            set @rate_id = 86;
                        when(@fee >= 900 and @fee <= 2199)then
                           set @rate_id = 87;
                        when(@fee > 2199 and @fee <= 3599)then
                           set @rate_id = 88;
                        when (@fee > 3599)then
                            set @rate_id = 89;
                    end case;
						select seller_PE_bg, seller_PE_bg, amount_captured, c.id
							into sale_amount_PE, sale_amount_US, captured_amount, id_commission
						from commissions c
                        where c.rate_id = @rate_id;
				end if;


				if(id_commission in (7, 8))then

					case
						when(fee < 999)then

							set id_commission =  7;

						when(fee >= 999 and fee <= 1500)then

							set id_commission =  8;

						when(fee > 1500 and fee <= 2000)then

							set id_commission =  32;

						when (fee > 2000)then

							set id_commission =  33;

					end case;



				elseif(id_commission in (29, 30))then

					case
						when(fee < 2000)then

							set id_commission = 29;

						when(fee >= 2000 and fee <= 3000)then

							set id_commission = 30;

						when(fee > 3000)then

							set id_commission = 31;

						end case;
				end if;

				select seller_PE_bg, seller_PE_bg, amount_captured
						into sale_amount_PE, sale_amount_US , captured_amount
				from commissions c
				where c.id = id_commission limit 1;

			elseif(id_program = 2)then
				select amount_captured,seller_PE_bg,seller_PE_bg
					into captured_amount,sale_amount_PE,sale_amount_US
				from commissions c
				where program_id = id_program and `description` like concat('%',fee,'%');
			elseif(id_program = 3)then

				if(fee > 0 and fee <= 1500)then
					set id_commission = 13;
				elseif(fee > 1500 and fee <= 3000)then
					set id_commission = 27;
				elseif(fee > 3000)then
					set id_commission = 28;
				end if;

				select amount_captured,seller_PE_bg,seller_PE_bg,seller_PE_bg,seller_PE_bg
					into captured_amount,sale_amount_PE,PE_percent,sale_amount_US,US_percent
				from commissions c
				where c.id = id_commission;

			elseif(id_program = 4 or id_program = 8) THEN

				select amount_captured,seller_PE_bg,seller_PE_bg into captured_amount,sale_amount_PE,sale_amount_US
				from commissions c
				where program_id = id_program;

			elseif(id_program = 5)then   

            	if(fee <= 500)then
            		set id_commission = 15;
            	elseif(fee > 500 and fee <= 1000) then

            		set id_commission = 38;
            	elseif(fee > 1000)then

            		set id_commission = 39;

            	end if;

            	select amount_captured,seller_PE_bg,seller_PE_bg,seller_PE_bg,seller_PE_bg
				into captured_amount,sale_amount_PE,PE_percent,sale_amount_US,US_percent
				from commissions c
				where c.id = id_commission;


			elseif(id_program = 6)then

				if(fee <= 400)then

					set id_commission = 34;

				elseif(fee > 400)then

					set id_commission = 16;

				end if;

				select seller_PE_bg, seller_PE_bg, amount_captured
					into sale_amount_PE, sale_amount_US, captured_amount
				from commissions c
				where c.id = id_commission;

			elseif(id_program = 7)then

				if(fee <= 400)then

					set id_commission = 35;

				elseif(fee > 400)then

					set id_commission = 17;

				end if;

				select seller_PE_bg, seller_PE_bg, amount_captured
					into sale_amount_PE, sale_amount_US, captured_amount
				from commissions c
				where c.id = id_commission;

			elseif(id_program = 9)then
				select case
						when senior = 1 then seller_PE_bg
						when senior = 2 then seller_PE_jr
						when senior = 3 then seller_PE_sr
						when senior = 4 then seller_PE_mr
					end, if(senior = 3, seller_US_sr, seller_US_jr), amount_captured, c.id
					into sale_amount_PE, sale_amount_US, captured_amount, id_commission
				from commissions c
					inner join rate_sales rs on rs.rate_id=c.rate_id
				where sale_id = id_sale and program_id = id_program;

			else

				set captured_amount = 0;
				set sale_amount_PE = 0;
				set sale_amount_US = 0;
			end if;

            IF (fee > 0) THEN
                
                select module_id into sale_module from sales where id = id_sale;
               
               
                select u.id into id_sup
                from users u
                join user_module um on um.user_id = u.id
                where um.module_id = 2
                and um.role_id = 2;

               	
				if(sale_module = 11) then
					select u.id into id_sup_department
					from users u
					join user_module um on um.user_id = u.id
					where um.module_id = sale_module
					and um.role_id = 2 and ifnull(id_seller,id_capture) = u.id limit 1;
				else
					select u.id into id_sup_department
					from users u
					join user_module um on um.user_id = u.id
					where um.module_id = sale_module
					and um.role_id = 2 limit 1;
				end if;
               
               
               SELECT value into percentage_commission_for_sup FROM ced_settings_commission_roles cscr 
			   WHERE module_id = sale_module and role_id = 2 limit 1;
                
                if((id_capture <> 1 and id_seller <> 1) and (id_capture <> id_sup and id_seller <> id_sup))then
                    if(id_capture = id_seller)then
                        set id_change = 1;
                        set captured_amount = 0;
                    end if;
                end if;
               
                
                
                
                IF (id_capture = id_sup_department) THEN
					set amount_commission_for_sup = 0;
				ELSE
					set commission_for_sup_capture = captured_amount;
				            	
					IF (commission_for_sup_capture is null) then
						set commission_for_sup_capture = 0;
					END IF;

					set amount_commission_for_sup = commission_for_sup_capture*(percentage_commission_for_sup/100);
				END IF;

                INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`,amount_for_sup,type_for)
                VALUES (id_sale,id_capture,captured_amount,1,id_change, amount_commission_for_sup, 2);
               
                set last_id_sales_commissions = @@identity;
                
				INSERT INTO general_commissions_supervisors
				(amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
				VALUES(amount_commission_for_sup, id_sup_department, last_id_sales_commissions, 2, 1, NOW(),2, sale_module);
			   

			
				
                set commissions_seller = sale_amount_PE;

                if (country_seller = 2) then
                    set commissions_seller=sale_amount_US;
                end if;
                
               
               
                
               
                IF (id_seller = id_sup_department) THEN
					set amount_commission_for_sup = 0;
				ELSE
	                set commission_for_sup_sale = commissions_seller;
	               
					if (commission_for_sup_sale is null ) then
						set commission_for_sup_sale = 0;
					end if;
				    
					set amount_commission_for_sup = commission_for_sup_sale*(percentage_commission_for_sup/100);
			    END IF;

                INSERT INTO sales_commissions (sale_id,user_id,commission,`type`,`change`, amount_for_sup, type_for)
                VALUES (id_sale,id_seller,commissions_seller,2,0, amount_commission_for_sup, 2);
                
                set last_id_sales_commissions = @@identity;
                
                INSERT INTO general_commissions_supervisors
				(amount, user_id, sale_commission_id, type_from, type_commission, created_at, status_commission, module_id)
				VALUES(amount_commission_for_sup, id_sup_department, last_id_sales_commissions, 2, 2, NOW(), 2, sale_module); 
               
                
                
            END IF;

        RETURN 1;
        END $$

DELIMITER ;



-- Archivo: get_available_stock_by_item.sql
DELIMITER $$

CREATE FUNCTION `get_available_stock_by_item`(_item_logistics_id INT) RETURNS int
BEGIN
            DECLARE cc INT DEFAULT 0;
            DECLARE PRODUCTS INT DEFAULT 2;
            
            
            DROP TEMPORARY TABLE IF EXISTS items_income_to_stock;
            CREATE TEMPORARY TABLE items_income_to_stock (
                item_id INT NOT NULL,
                total_income_quantity INT NOT NULL,
                INDEX idx_item_id (item_id)
            ) ENGINE = MEMORY
            AS (
                SELECT item_id, SUM(income_quantity) total_income_quantity FROM
                (
                    (
                        
                        SELECT pod.item_id item_id, SUM(pod.quantity) income_quantity
                            FROM purchase_order po 
                            LEFT JOIN purchase_order_detail pod ON po.id = pod.purchase_order_id
                            WHERE pod.item_id = _item_logistics_id AND po.approved_at IS NOT NULL
                            and po.purchase_type_id not in (2,3)
                            GROUP BY pod.item_id
					)
                    UNION ALL 
                    (
                        
                        SELECT idl.item_id item_id, COUNT(idl.item_id) income_quantity
                            FROM item_detail_logistic idl
                            WHERE idl.item_id = _item_logistics_id AND idl.purchase_order_id IS NULL
                            GROUP BY idl.item_id
                    )
                    UNION ALL
                        
                    ( SELECT id item_id, initial_stock income_quantity FROM items_logistic il WHERE il.id = _item_logistics_id )
                ) AS incomes GROUP BY item_id
            );

            
            DROP TEMPORARY TABLE IF EXISTS not_available_stock_by_item;
            CREATE TEMPORARY TABLE not_available_stock_by_item (
                item_id INT NOT NULL,
                not_available_stock INT NOT NULL,
                INDEX idx_item_id (item_id)
            ) ENGINE = MEMORY
            AS (
                SELECT nas.item_id, SUM(nas.not_available) AS not_available_stock
                    FROM (
                    (
                         
                        SELECT irdl.item_id AS item_id, SUM(irdl.quantity) AS not_available
                            FROM item_request_logistic irl
                            LEFT JOIN item_request_detail_logistic irdl ON irdl.item_request_id = irl.id
                            LEFT JOIN items_logistic irls ON irls.id = irdl.item_id
                            LEFT JOIN subcategory_logistic sl ON sl.id = irls.sub_category_id
                            LEFT JOIN category_logistic cl ON cl.id = sl.category_id
                            WHERE irdl.item_id = _item_logistics_id
                              AND cl.id = PRODUCTS 
                              AND irl.status = 'DELIVERED'
                              AND irdl.status = 'APPROVED' 
                              AND irdl.asigned_to IS NOT NULL
                            GROUP BY irdl.item_id
                    )

                    UNION ALL

                    (
                        
                        SELECT idl.item_id AS item_id, COUNT(idl.condition_status) AS not_available
                            FROM item_detail_logistic idl
                            LEFT JOIN items_logistic irls ON irls.id = idl.item_id
                            LEFT JOIN subcategory_logistic sl ON sl.id = irls.sub_category_id
                            LEFT JOIN category_logistic cl ON cl.id = sl.category_id
                            WHERE idl.item_id = _item_logistics_id AND cl.id <> PRODUCTS AND ( 
                                idl.condition_status = 'DAMAGED'
                                OR idl.availability_status = 'REMOVED'
                                OR idl.availability_status = 'ASSIGNED' )
                            GROUP BY idl.item_id
                    )) nas
                    GROUP BY nas.item_id
            );

            
            DROP TEMPORARY TABLE IF EXISTS reserved_stock_by_item;
            CREATE TEMPORARY TABLE reserved_stock_by_item (
                item_id INT NOT NULL,
                reserved_stock INT NOT NULL,
                INDEX idx_item_id (item_id)
            ) ENGINE = MEMORY
            AS (
                SELECT t_reserved.item_id AS item_id, SUM(t_reserved.reserved) AS reserved_stock FROM
                (
                    (
                        SELECT irdl.item_id AS item_id, SUM(irdl.quantity) AS reserved
                        FROM item_request_logistic irl
                        LEFT JOIN item_request_detail_logistic irdl ON irdl.item_request_id = irl.id
                        LEFT JOIN items_logistic irls ON irls.id = irdl.item_id
                        LEFT JOIN subcategory_logistic sl ON sl.id = irls.sub_category_id
                        LEFT JOIN category_logistic cl ON cl.id = sl.category_id
                        WHERE irdl.item_id = _item_logistics_id
                          AND cl.id = PRODUCTS
                          AND irl.status = 'DELIVERED'
                          AND irdl.status = 'APPROVED'
                          AND irdl.asigned_to IS NULL
                        GROUP BY irdl.item_id
                    )
                    UNION ALL
                    (
                        SELECT idl.item_id AS item_id, COUNT(idl.condition_status) AS reserved
                            FROM item_detail_logistic idl
                            LEFT JOIN items_logistic irls ON irls.id = idl.item_id
                            LEFT JOIN subcategory_logistic sl ON sl.id = irls.sub_category_id
                            LEFT JOIN category_logistic cl ON cl.id = sl.category_id
                            WHERE idl.item_id = _item_logistics_id AND cl.id <> PRODUCTS AND idl.availability_status = 'RESERVED'
                            GROUP BY idl.item_id
                    )
                ) t_reserved GROUP BY t_reserved.item_id
            );

            SELECT
                ( iits.total_income_quantity - IFNULL(nasbi.not_available_stock, 0) - IFNULL(rsbi.reserved_stock, 0) ) INTO cc
            FROM items_logistic il
            LEFT JOIN not_available_stock_by_item nasbi ON nasbi.item_id = il.id
            LEFT JOIN reserved_stock_by_item rsbi ON rsbi.item_id = il.id
            LEFT JOIN items_income_to_stock iits ON iits.item_id = il.id
            WHERE il.id = _item_logistics_id; 

            RETURN IFNULL(cc, 0);
        END $$

DELIMITER ;



-- Archivo: get_average_score.sql
DELIMITER $$

CREATE FUNCTION `get_average_score`(equ int, exp int, tra int) RETURNS int
BEGIN
	declare total int;
    
	if(equ <> 0 and exp <> 0 and tra <> 0)then
    
		set total = case
			when equ > exp and equ < tra or equ < exp and equ > tra then equ
			when exp > equ and exp < tra or exp < equ and exp > tra then exp
			when tra > equ and tra < exp or tra < equ and tra > exp then tra
		end;
        
	else
        if(equ > 0 and exp > 0)then
        
			set total = case
						when equ > exp then equ
                        when equ < exp then exp
                        end;
                        
		elseif(exp > 0 and tra > 0)then
        
			set total = case
						when tra > exp then tra
                        when tra < exp then exp
                        end;
                        
		elseif(equ > 0 and tra > 0)then
        
			set total = case
						when tra > equ then tra
                        when tra < equ then equ
                        end;
                        
		elseif(equ > 0)then
			set total = equ;
            
		elseif(exp > 0)then
			set total = exp;
            
		elseif(tra > 0)then
			set total = tra;
            
        end if;
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: get_bank_accounts.sql
DELIMITER $$

CREATE FUNCTION `get_bank_accounts`(
             _payment_order_amount DECIMAL(11, 2),
            _bank_account_type ENUM('AMG', 'CLIENT'),
            _bank_account_status ENUM('Active', 'Inactive', 'Suspended')
        ) RETURNS json
BEGIN
        DECLARE _bank_accounts_data_json JSON;
            DROP TEMPORARY TABLE IF EXISTS _bank_account_data_table;
            CREATE TEMPORARY TABLE _bank_account_data_table (
                bank_account_id INT,
                total_balance DECIMAL(11, 2),
                available_balance DECIMAL(11, 2),
                bank_account_type ENUM('AMG', 'CLIENT'),
                bank_account_routing_number VARCHAR(255),
                bank_account_number VARCHAR(255),
                bank_account_address VARCHAR(255),
                bank_account_status ENUM('Active', 'Inactive', 'Suspended'),
                bank_account_name VARCHAR(255),
                checkbook_numbers JSON,
                checkbook_ids JSON,
                range_checkbook_physical JSON
            ) ENGINE=MyISAM;


            INSERT INTO _bank_account_data_table
                ( bank_account_id,
                  total_balance,
                  available_balance,
                  bank_account_type,
                  bank_account_routing_number,
                  bank_account_number,
                  bank_account_address,
                  bank_account_status,
                  bank_account_name,
                  checkbook_numbers,
                  checkbook_ids,
                  range_checkbook_physical)
            SELECT
               dba.id bank_account_id,
               dba.balance total_balance,
               dba.balance - SUM(IF(dopo.payment_order_status_id = 1, dopo.amount, 0)) available_balance,
               dba.`type` bank_account_type,
               dba.routing_number bank_account_routing_number,
               dba.account_number bank_account_number,
               dba.address bank_account_address,
               dba.status bank_account_status,
               dba.account_name bank_account_name,
               (SELECT JSON_OBJECTAGG( IF(dc.`type` = 'Virtual', 'virtual_checkbook_number', 'physical_checkbook_number'), dc.`number` )
                FROM ds_checkbooks dc WHERE dc.bank_account_id = dba.id AND ( _bank_account_status IS NULL OR dc.status = _bank_account_status ) ) checkbook_numbers,
               (SELECT JSON_OBJECTAGG( IF(dc.`type` = 'Virtual', 'virtual_checkbook_id', 'physical_checkbook_id'), dc.`id` )
                FROM ds_checkbooks dc WHERE dc.bank_account_id = dba.id AND ( _bank_account_status IS NULL OR dc.status = _bank_account_status ) ) checkbook_ids,
               (SELECT JSON_OBJECT('range_from',dc.range_from, 'range_to',dc.range_to)
               	FROM ds_checkbooks dc WHERE dc.bank_account_id = dba.id AND ( _bank_account_status IS NULL OR dc.status = _bank_account_status ) AND dc.`type`='Physical') range_checkbook_physical

            FROM ds_bank_accounts dba
            LEFT JOIN ds_offer_payment_orders dopo ON dba.id = dopo.bank_account_id
            GROUP BY dba.id
            HAVING (available_balance - IFNULL(_payment_order_amount, 0) >= 0)
               AND (_bank_account_status IS NULL OR bank_account_status = _bank_account_status)
               AND (_bank_account_type IS NULL OR bank_account_type = _bank_account_type);

            SET _bank_accounts_data_json =
                (SELECT JSON_ARRAYAGG(JSON_OBJECT(
                      'bank_account_id', bank_account_id,
                      'total_balance', total_balance,
                      'available_balance', available_balance,
                      'bank_account_type', bank_account_type,
                      'bank_account_routing_number', bank_account_routing_number,
                      'bank_account_number', bank_account_number,
                      'bank_account_address', bank_account_address,
                      'bank_account_status', bank_account_status,
                      'bank_account_name', bank_account_name,
                      'checkbook_numbers', checkbook_numbers,
                      'checkbook_ids', checkbook_ids,
                      'range_checkbook_physical', range_checkbook_physical
                  ))
                  FROM _bank_account_data_table);

            IF(JSON_LENGTH(_bank_accounts_data_json) > 0) THEN
              RETURN _bank_accounts_data_json;
              ELSE
              RETURN '{}';
            END IF;
        END $$

DELIMITER ;



-- Archivo: get_charge_paid_p.sql
DELIMITER $$

CREATE FUNCTION `get_charge_paid_p`(date_month int, date_year int, id_program int, id_type int) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    declare _date date;
    declare _last_day date;
	set _date = date(concat(date_year,'-',date_month,'-01'));
    set _last_day = last_day(_date);
    set @type_automatic := 1;
    set @type_charge := 7;
    set @type_manual := 2;
    set @method_cashier := 7;
    set @modality_monthly := 1;

    if(id_type = 0)then 

        select cast(replace(new_global_income_monthly(_date,id_program,0),',','') as decimal(19,2)) into total ;

    elseif(id_type = 1)then 

		SELECT
            sum(ac.amount) into total
        FROM additional_charges ac
        LEFT JOIN types_charges tc ON ac.type_charge = tc.id
        LEFT JOIN users col ON col.id = ac.user_id
        JOIN transactions t ON ac.transactions_id = t.id
        JOIN client_accounts ca ON ac.client_acount_id = ca.id
        JOIN programs p ON p.id = ca.program_id 
        JOIN clients c ON ca.client_id = c.id
        JOIN leads l ON c.lead_id = l.id
        WHERE t.status_transaction_id IN (1, 5)
        AND t.settlement_date >= _date
        AND t.settlement_date < DATE_ADD(_last_day, INTERVAL 1 DAY)
        AND t.modality_transaction_id NOT IN ( 1,2 )
        and t.type_transaction_id not in (3,10,11,14,15,16,17) and
        ca.program_id = id_program;

    elseif(id_type = 2)then 

        set total = (select case
				when date_month = 1 then sum(p_jan)
                when date_month = 2 then sum(p_feb)
                when date_month = 3 then sum(p_mar)
                when date_month = 4 then sum(p_apr)
                when date_month = 5 then sum(p_may)
                when date_month = 6 then sum(p_jun)
                when date_month = 7 then sum(p_jul)
                when date_month = 8 then sum(p_aug)
                when date_month = 9 then sum(p_sep)
                when date_month = 10 then sum(p_oct)
                when date_month = 11 then sum(p_nov)
                when date_month = 12 then sum(p_dec)
				end
		from generate_report_global_ad
        where year = date_year
        and module_id <> 2);

    elseif(id_type = 3)then 

        set total = (select case
				when date_month = 1 then sum(c_jan)
                when date_month = 2 then sum(c_feb)
                when date_month = 3 then sum(c_mar)
                when date_month = 4 then sum(c_apr)
                when date_month = 5 then sum(c_may)
                when date_month = 6 then sum(c_jun)
                when date_month = 7 then sum(c_jul)
                when date_month = 8 then sum(c_aug)
                when date_month = 9 then sum(c_sep)
                when date_month = 10 then sum(c_oct)
                when date_month = 11 then sum(c_nov)
                when date_month = 12 then sum(c_dec)
				end
		from generate_report_global_ad
        where year = date_year
        and module_id <> 2);

    elseif(id_type = 4)then 

        select sum(total_paid) into total
		from generate_report_global_ad
        where year = date_year
        and module_id <> 2;

    elseif(id_type = 5)then 

        select sum(total_charge) into total
		from generate_report_global_ad
        where year = date_year
        and module_id <> 2;

    elseif(id_type = 6)then 

        set total = (select case
				when date_month = 1 then sum(ifnull(p_jan,0)) + sum(ifnull(c_jan,0))
                when date_month = 2 then sum(ifnull(p_feb,0)) + sum(ifnull(c_feb,0))
                when date_month = 3 then sum(ifnull(p_mar,0)) + sum(ifnull(c_mar,0))
                when date_month = 4 then sum(ifnull(p_apr,0)) + sum(ifnull(c_apr,0))
                when date_month = 5 then sum(ifnull(p_may,0)) + sum(ifnull(c_may,0))
                when date_month = 6 then sum(ifnull(p_jun,0)) + sum(ifnull(c_jun,0))
                when date_month = 7 then sum(ifnull(p_jul,0)) + sum(ifnull(c_jul,0))
                when date_month = 8 then sum(ifnull(p_aug,0)) + sum(ifnull(c_aug,0))
                when date_month = 9 then sum(ifnull(p_sep,0)) + sum(ifnull(c_sep,0))
                when date_month = 10 then sum(ifnull(p_oct,0)) + sum(ifnull(c_oct,0))
                when date_month = 11 then sum(ifnull(p_nov,0)) + sum(ifnull(c_nov,0))
                when date_month = 12 then sum(ifnull(p_dec,0)) + sum(ifnull(c_dec,0))
				end
		from generate_report_global_ad
        where year = date_year
        and module_id <> 2);

	elseif(id_type = 7)then 

        select sum(t.amount) into total
		from transactions t
			join client_accounts ca on ca.id = t.client_acount_id
		where ca.program_id = id_program
		and t.type_transaction_id in (@type_automatic,@type_manual)
        and not (t.method_transaction_id = @method_cashier and t.modality_transaction_id = @modality_monthly)
        and t.status_transaction_id in (1,5)
		and (date(t.settlement_date) >= date(concat(date_year,'-01-01')) and (date(t.settlement_date) <= last_day(date(concat(date_year,'-12-01')))));

	elseif(id_type = 8)then 

		select sum(t.amount) into total
		from transactions t
			join client_accounts ca on ca.id = t.client_acount_id
		where ca.program_id = id_program
		and t.type_transaction_id = @type_charge
        and t.status_transaction_id in (1,5)
		and (date(t.settlement_date) >= date(concat(date_year,'-01-01')) and (date(t.settlement_date) <= last_day(date(concat(date_year,'-12-01')))));

	end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: get_charged_payments.sql
DELIMITER $$

CREATE FUNCTION `get_charged_payments`(`datem` date) RETURNS decimal(16,2)
BEGIN
           declare total_positive_amount decimal(11,2);
            declare total_negative_amount decimal(11,2);
            declare total decimal(11,2);

            declare type_automatic int;
            declare type_manual int;
            declare type_charge_back int;

            declare method_card int;
            declare method_deposit int;
            declare method_zelle int;
            
            declare modality_monthly int;
            declare modality_penality int;
            declare modality_return int;
            
            declare ce_module_id int;
            declare status_approved int;
            declare status_settled_success int;
            declare status_chargeback int;

            set ce_module_id = 3;

            set type_automatic = 1;
            set type_manual = 2;
            set type_charge_back = 15;
            
            set method_card = 1;
            set method_deposit = 5;
            set method_zelle = 6;

            set modality_monthly = 1;
            set modality_penality =  5;
            set modality_return = 6;

            set status_approved = 1;
            set status_settled_success = 5;
            set status_chargeback = 9;


            set total_positive_amount = (select sum(amount)
                from ( (
                        select t.settlement_date,t.id,t.amount,'Monthly payment' type
                        from transactions t
                        join client_accounts ca on t.client_acount_id = ca.id
                        where t.status_transaction_id in (1,5)
                            and 
                            (   t.type_transaction_id = type_automatic
                                or 
                                (
                                    t.type_transaction_id = type_manual 
                                    and 
                                    (
                                        t.method_transaction_id = method_deposit 
                                        or 
                                        t.method_transaction_id = method_card
                                    )
                                )
                            )
                            and t.method_transaction_id in (method_card,method_deposit,method_zelle)
                            and ca.program_id=ce_module_id 
                            and (t.settlement_date BETWEEN datem AND LAST_DAY(datem))
                            )
                            union
                        (select t.settlement_date,t.id,t.amount,'Charge back ' type
                        from transactions t
                        join client_accounts ca on t.client_acount_id = ca.id
                        where t.type_transaction_id = type_charge_back
                        and t.modality_transaction_id = modality_return
                        and ca.program_id = ce_module_id 
                        and (t.settlement_date BETWEEN datem AND LAST_DAY(datem))
                        and status_transaction_id in (status_approved,status_settled_success,status_chargeback))) p);


            set total_negative_amount = (select sum(amount)
                from ((select t.settlement_date,t.id,t.amount,'Charge back' type
                        from transactions t
                        join client_accounts ca on t.client_acount_id = ca.id
                        where t.type_transaction_id in (type_charge_back)
                        and ( t.modality_transaction_id is null or t.modality_transaction_id = modality_penality) 
                        and ca.program_id = ce_module_id 
                        and (t.settlement_date BETWEEN datem AND LAST_DAY(datem))
                        and status_transaction_id in (status_approved,status_settled_success,status_chargeback))) p);

            set total = (select total_positive_amount - ifnull(total_negative_amount,0));
            return total;
        END $$

DELIMITER ;



-- Archivo: get_current_amount_paid_in_payment_schedule.sql
DELIMITER $$

CREATE FUNCTION `get_current_amount_paid_in_payment_schedule`(_payment_schedule_id BIGINT) RETURNS decimal(18,2)
BEGIN
            DECLARE _current_amount_paid DECIMAL(18,2) DEFAULT 0;
            set @type_void = 10;
            set @type_refund = 11;
            set @type_void_parcial=16;
            set @type_refund_parcial=17;
            set @modality_monthly = 1;
        
            SELECT COALESCE(SUM(amount), 0)
            INTO _current_amount_paid
            FROM
            (   
                SELECT COALESCE(SUM(psd.amount_paid), 0) AS amount
                FROM payment_schedule_detail psd
                LEFT JOIN transactions t ON t.id = psd.transaction_id
                WHERE psd.payment_schedule_id = _payment_schedule_id
                AND t.status_transaction_id IN (1, 5, 8)
                AND t.type_transaction_id NOT IN (@type_void, @type_refund, @type_void_parcial, @type_refund_parcial)
        
                UNION ALL
        
                
                SELECT -1 * COALESCE(SUM(t.amount), 0) AS amount
                FROM partial_refunds_tranctions prt
                JOIN transactions t ON t.transaction_id = prt.transaction_id
                JOIN transactions t2 ON t2.transaction_id = prt.ref_transaction
                JOIN payment_schedule_detail psd ON psd.transaction_id = t2.id
                WHERE psd.payment_schedule_id = _payment_schedule_id
                AND t.status_transaction_id IN (1, 5, 8)
                AND t.modality_transaction_id = @modality_monthly
                AND t.type_transaction_id = @type_refund_parcial
        
                UNION ALL
        
                
                SELECT -1 * COALESCE(SUM(t.amount), 0) AS amount
                FROM pending_void_transactions pvt
                JOIN transactions t ON t.transaction_id = pvt.transaction_id
                JOIN transactions t2 ON t2.transaction_id = pvt.ref_transaction
                JOIN payment_schedule_detail psd ON psd.transaction_id = t2.id
                WHERE psd.payment_schedule_id = _payment_schedule_id
                AND t.status_transaction_id IN (1, 5, 8)
                AND t.modality_transaction_id = @modality_monthly
                AND t.type_transaction_id = @type_void_parcial
            ) AS total_current_amount_paid;
        
            RETURN _current_amount_paid;
        END $$

DELIMITER ;



-- Archivo: get_duration_value.sql
DELIMITER $$

CREATE FUNCTION `get_duration_value`() RETURNS int
BEGIN
            DECLARE duration_value INT;
            SET duration_value = 45;
            RETURN duration_value;
        END $$

DELIMITER ;



-- Archivo: get_employee_number.sql
DELIMITER $$

CREATE FUNCTION `get_employee_number`() RETURNS varchar(7) CHARSET latin1
BEGIN
                declare n int;
                
                select `min` into n from hr_configs where id=1;
                
                update hr_configs set `min`=`min`+1 where id=1;
                
            RETURN (select concat('EMP',substr(concat('0000',n),-4,4)));
            END $$

DELIMITER ;



-- Archivo: get_employee_salary.sql
DELIMITER $$

CREATE FUNCTION `get_employee_salary`(_employee_id varchar(255),_month int,_year int) RETURNS decimal(10,2)
BEGIN
          DECLARE salary DECIMAL(10,2) default 0;
          SELECT  
              CASE 
                  WHEN COUNT(*) = 1 THEN MAX(sa.new_salary)
                  WHEN MAX(LAST_DAY(sa.updated_at)) < LAST_DAY(CONCAT_WS('-', _year, _month, '01')) THEN MAX(sa.new_salary)
                  ELSE MAX(sa.old_salary)
              END AS amount INTO salary
          FROM salary_records sa
          JOIN employees e ON e.id = sa.employee_id
          WHERE e.id = _employee_id
              AND (YEAR(sa.updated_at) < _year OR (YEAR(sa.updated_at) = _year AND MONTH(sa.updated_at) <= _month))
          GROUP BY sa.employee_id;

          
          
          

          RETURN CAST(salary AS DECIMAL(10,2) ) ;
	      END $$

DELIMITER ;



-- Archivo: get_employee_schedule.sql
DELIMITER $$

CREATE FUNCTION `get_employee_schedule`(employee_id int, mark_time date) RETURNS int
BEGIN
            DECLARE hoursWorked INT;
    SELECT IFNULL(
        (
            SELECT 
                IF(TIMEDIFF(es.work_end_time, es.work_start_time) > '06:00:00', 8, 6) AS hours_worked
            FROM 
                employees_schedule_tracking es 
                JOIN employees e ON e.id = es.employee_id 
            WHERE 
                e.id_user = employee_id
                AND es.created_at < mark_time
                AND es.day_of_the_week = DAYOFWEEK(mark_time) 
            ORDER BY 
                es.created_at DESC 
            LIMIT 1
        ),
        (
            SELECT 
                8 AS hours_worked
            FROM 
                (SELECT 1) AS a 
            LIMIT 1
        )
    ) INTO hoursWorked;
    RETURN hoursWorked;
            END $$

DELIMITER ;



-- Archivo: get_employee_schedule_tolerance.sql
DELIMITER $$

CREATE FUNCTION `get_employee_schedule_tolerance`(employee_id int, mark_time date) RETURNS int
BEGIN
                     DECLARE hoursWorked INT;
    SELECT IFNULL(
        (
            SELECT
                es.id  AS hours_worked
            FROM
                employees_schedule_tracking es
                JOIN employees e ON e.id = es.employee_id
            WHERE
                e.id_user = employee_id
                AND es.created_at < mark_time
                AND es.day_of_the_week = DAYOFWEEK(mark_time)
            ORDER BY
                es.created_at DESC
            LIMIT 1
        ),
        (
            SELECT
                8 AS hours_worked
            FROM
                (SELECT 1) AS a
            LIMIT 1
        )
    ) INTO hoursWorked;
    RETURN hoursWorked;
            END $$

DELIMITER ;



-- Archivo: get_event_id_accounts_negotiate.sql
DELIMITER $$

CREATE FUNCTION `get_event_id_accounts_negotiate`(p_id_account CHAR(36)) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
            DECLARE v_ncr_request_id INT DEFAULT 0;
            DECLARE v_result VARCHAR(255);
        
            SELECT raa.ncr_request_id INTO v_ncr_request_id
            FROM cr_accounts_ac caa
            INNER JOIN analysis_accounts_negotiate aan ON aan.cr_account_ac_id = caa.id
            INNER JOIN result_analysis_account raa ON raa.id = aan.result_analysis_account_id 
            WHERE caa.lead_id = (SELECT c.lead_id FROM client_accounts ca INNER JOIN clients c ON c.id = ca.client_id WHERE ca.id = p_id_account)
            GROUP BY raa.ncr_request_id, raa.created_at
            ORDER BY raa.created_at DESC
            LIMIT 1;
        
            SELECT dlc.event_id INTO v_result FROM ds_list_credits dlc
            join sales s on dlc.event_id = s.event_id
            WHERE dlc.ncr_request_id = v_ncr_request_id and s.status_id != 9
            GROUP BY dlc.event_id;
        
            RETURN v_result;
        END $$

DELIMITER ;



-- Archivo: get_financial_review.sql
DELIMITER $$

CREATE FUNCTION `get_financial_review`(lead_id INT, _option INT, _total_current_situation DECIMAL(10,2), _monthp_current_situation DECIMAL(10,2) , _current_debt decimal(10,2), event_id INT ) RETURNS json
BEGIN
		DECLARE total_registered_account DECIMAL(10,2);
																			  DECLARE current_interest DECIMAL(10,2);
																			  DECLARE monthly_pay DECIMAL(10,2);
																			  DECLARE program_payment DECIMAL(10,2);
																			  DECLARE retainer_fee DECIMAL(10,2);
																			  DECLARE total_creditors INT;
																		 
																			 set @percentage = case 
																				when _option = 3 then 0.9
																				when _option = 4 then 0.75
																				when _option = 5 then 0.6
																				else 1
																				end;
																		
																			select cast(sum(ifnull(dlc.balance,0)) as DECIMAL(10,2)),count(dlc.id),sum(dlc.interest),
																					cast(sum(ifnull(dlc.monthly,0)) as decimal(10,2)) into 
																					total_registered_account, total_creditors, current_interest, monthly_pay from events e 
																			join ds_list_credits dlc on dlc.event_id = e.id
																			where e.id = event_id;
																		
																			select ifnull(e.program_payment,0), ifnull(e.retainer_fee,0) into program_payment, retainer_fee  from events e 
																			where e.id = event_id order by e.created_at desc limit 1;
																		
																			set @current_debt = case
																				when _option = 3 or _option = 4 or _option = 5 then cast((IFNULL((total_registered_account *  @percentage),0)) as decimal(10,2))
																				else IFNULL(total_registered_account,0) 
																				end;
																			
																			set @monthly_payment = case
																				when _option = 2 then ( _monthp_current_situation * 0.7)
																				when _option = 3 then program_payment
																				when _option = 5 then @current_debt
																				when _option = 6 or _option = 7 then 0
																				else IFNULL(monthly_pay,0) 
																				end;
																		
																			set @interest = case 
																				when (_option = 1 and total_creditors > 0 ) then (current_interest / total_creditors)
																				when (_option = 2 and total_creditors > 0) then (( current_interest / total_creditors) - 7 )
																				else 0
																				end;
																			
																			set @interest_year = case 
																				when ((_option = 1 or _option = 2) and total_creditors > 0 ) then cast( (@current_debt * ( @interest / 100 )) as decimal(10,2))
																				else 0
																				end;
																			
																			set @interest_monthly = case 
																				when ((_option = 1 or _option = 2) and total_creditors > 0 ) then cast( (@interest_year / 12) as decimal(10,2))
																				else 0
																				end;
																			
																			set @interest_daily = case 
																				when ((_option = 1 or _option = 2) and total_creditors > 0) then cast( (@interest_monthly / 30) as decimal(10,2))
																				else 0
																				end;
																			
																			set @payment_principal = case
																				when _option = 1 then cast( (@monthly_payment - @interest_monthly) as decimal(10,2))
																				when _option = 2 then cast( (@monthly_payment - (@interest_monthly - (@monthly_payment  *  0.05)) ) as decimal(10,2))
																				when _option = 3 then program_payment
																				when _option = 4 or _option = 5 then @monthly_payment
																				else 0
																				end;
																			
																			set @payment_time = case 
																				when ((_option = 1 or _option = 2) and total_creditors > 0) then cast((@current_debt / @payment_principal) as decimal(10,0))
																				when ((_option = 3 or _option = 4) and total_creditors > 0) then cast((@current_debt / @monthly_payment ) as decimal(10,0))
																				when _option = 5 then 1
																				else 12
																				end;
																			
																			set @service_payment = case
																				when _option = 1 then "N/A"
																				when _option = 2 then cast( (@monthly_payment * 0.05) as decimal(10,2))
																				when _option = 3 or _option = 4 then if(retainer_fee > 0,cast( (_current_debt * retainer_fee) as decimal(10,2)), format(0,2)) 
																				when _option = 5 then format(0,2)
																				else "$ 1.5k - $ 5K"
																				end;
																			
																			set @total_debt = case
																				when _option = 1 or _option = 2 then cast( ( @current_debt + (@interest_monthly * @payment_time) ) as decimal(10,2))
																				when _option = 6 then 0
																				when _option = 7 then cast( (_current_debt/2) as decimal(10,2))
																				else  @current_debt
																				end;
																			
																			set @saving = case
																				when _option = 1 or _option = 2 then 0
																				when _option = 6 then @current_debt
																				when _option = 7 then cast( (@current_debt/2) as decimal(10,2))
																				else cast( (_total_current_situation - @total_debt) as decimal(10,2))
																				end;
																			
																
																			
																		  RETURN JSON_OBJECT("current_debt",FORMAT(@current_debt,2), "monthly_payment",format(@monthly_payment,2), 
																							 "interest", format(@interest,2), "interest_year",format(@interest_year,2),
																							 "interest_monthly", format(@interest_monthly,2), "interest_daily",format(@interest_daily,2),
																							 "payment_principal", format(@payment_principal,2), "payment_time", @payment_time, 
																							 "total_debt",format(@total_debt,2),
																							 "saving", format(@saving,2),"service",@service_payment);
																						
																		END $$

DELIMITER ;



-- Archivo: get_hours_assigned.sql
DELIMITER $$

CREATE FUNCTION `get_hours_assigned`(user_p int, module_p int, date_p date) RETURNS int
begin
            set @break = (
                select timediff(s.finish_break , s.begining_break) from schedules s 
            where s.id_user = user_p and s.module_id = module_p and s.`date` = date_p);
        
            set @hours = (
                select 
                date_format(if(s.count_break = 1 or s.count_break is null,
                    subtime(timediff(s.checkout, s.checking), timediff(s.finish_break, s.begining_break)),
                    timediff(s.checkout, s.checking)
                    ), "%H") * 1
                from schedules s 
            where s.id_user = user_p and s.module_id = module_p and s.`date` = date_p);
            
        
            
            return  @hours;
        END $$

DELIMITER ;



-- Archivo: get_hours_discount.sql
DELIMITER $$

CREATE FUNCTION `get_hours_discount`(_id_user varchar(255) ,not_worked_hours int,
        _month int,_year int ) RETURNS decimal(10,2)
BEGIN
                  DECLARE salary_per_hour decimal(10,2);
                    DECLARE error_message VARCHAR(255);
                    DECLARE discount decimal(10,2);
                    DECLARE error_info VARCHAR(255);
                    DECLARE salary decimal(10,2);
                    declare base_salary decimal(10,2);

                
                    DECLARE EXIT HANDLER FOR SQLEXCEPTION
                
                    BEGIN
                        GET DIAGNOSTICS CONDITION 1 error_info = MESSAGE_TEXT;
                        SET error_message = CONCAT('Error: ', SUBSTRING_INDEX(error_info, ' - ', 1));
                        
                        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
                    END;

                     SELECT get_employee_salary(_id_user,_month,_year) INTO salary;
                     select IFNULL((select value from payment_settings ps where ps.slug='SEP' and updated_at is null and updated_by is null
                     and companie_id= (select companie_id from employees e where e.id_user=_id_user)
                     ),71
                     ) INTO base_salary;

                     set salary=salary;

                    IF salary<0 THEN
                    SET error_message='Salary cannot be lower than 0';
                        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
                    END IF;
                

                        SET salary_per_hour =cast(salary / 240 as decimal(10,2));

                        SET discount =if(salary_per_hour * not_worked_hours<0,0,cast(salary_per_hour * not_worked_hours as decimal(10,2)));

                
                        IF discount < 0 THEN
                            SET error_message = 'The discount value cannot be negative.';
                            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
                

                        ELSEIF discount>salary THEN
                                SET error_message = 'The discount value cannot be greater than salary';
                            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
                        ELSE
                            RETURN cast(discount as decimal(10,2));

                    END IF;

        END $$

DELIMITER ;



-- Archivo: get_hours_worked.sql
DELIMITER $$

CREATE FUNCTION `get_hours_worked`(user_p int, module_p int, date_p date) RETURNS int
begin
                    set @validate = (select if(ms.m_checkout is null, 0, 1) from mark_schedules ms where ms.id_user = user_p and ms.module_id = module_p and ms.`date` = date_p);
                    
                       
                    if(@validate = 1 )then
                    
                            set @hours = (select
                            
                            TIME_FORMAT(subtime(if(ms.status = 1 && ifnull(js.appv_rrhh, 0) != 1,
                            subtime(timediff(ms.m_checkout, TIME_FORMAT(ms.m_checking, "%H:00:00")), "01:00:00"),
                            timediff(ms.m_checkout, s.checking))
                             ,
                            if(s.count_break = 1 or s.count_break is null ,
                              ifnull(timediff(ms.m_finish_break, ms.m_begining_break), "00:00:00"), "00:00:00")
                            ), "%H") * 1
                             
                          
                        from
                            mark_schedules ms
                            join schedules s on ms.id_user = s.id_user and ms.module_id = s.module_id and ms.`date` = s.`date` 
                        left join justify_schedules js on 
                        ms.id_user = js.id_user and ms.module_id = js.module_id and ms.`date` = js.date_sch  
                        where
                            (user_p is null
                            or ms.id_user = user_p)
                            and (module_p is null
                            or ms.module_id = module_p)
                            and (date_p is null
                            or ms.`date` = date_p));
                            return @hours;
                    else 
                         return 0;
                    end if;
                END $$

DELIMITER ;



-- Archivo: get_initial_payment_in_payment_schedule.sql
DELIMITER $$

CREATE FUNCTION `get_initial_payment_in_payment_schedule`(_sales_id INT) RETURNS decimal(18,2)
BEGIN
            DECLARE _initial_payment DECIMAL(18,2);
            
            set @type_void = 10;
            set @type_refund = 11;
            set @type_charge_back = 15;
            set @type_void_parcial=16;
            set @type_refund_parcial=17;
            set @modality_initial = 2;
        
            SELECT COALESCE(SUM(amount), 0)
            INTO _initial_payment
            FROM(
                SELECT COALESCE(SUM(t.amount), 0) amount
                FROM transactions t 
                WHERE t.sale_id = _sales_id
                AND t.modality_transaction_id = @modality_initial
                AND t.status_transaction_id IN (5, 8, 1)
                AND t.type_transaction_id NOT IN (@type_void, @type_refund, @type_void_parcial, @type_refund_parcial, @type_charge_back)
                AND t.idchargeback IS NULL
                
                UNION 
        
                SELECT COALESCE(SUM(t.amount), 0) amount
                FROM initial_payments ip
                JOIN transactions t ON t.id = ip.transactions_id 
                WHERE ip.sale_id = _sales_id
                AND t.status_transaction_id IN (5, 8, 1)
                AND t.type_transaction_id NOT IN (@type_void, @type_refund, @type_void_parcial, @type_refund_parcial, @type_charge_back)
                AND t.idchargeback IS NULL
            ) AS initial_payments;
        
            RETURN _initial_payment;
        END $$

DELIMITER ;



-- Archivo: get_ip_others.sql
DELIMITER $$

CREATE FUNCTION `get_ip_others`(date_month int, date_year int, id_type int) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    set @type_initial := 3;
    set @type_others := 6;
    if(id_type = 0)then 

		SELECT
			IFNULL(SUM(ip.amount), 0) INTO total
			FROM sales s
			JOIN initial_payments ip ON s.id = ip.sale_id
			JOIN programs p ON p.id = s.program_id 
			WHERE s.initial_payment_status = 2
        and (date(ip.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(ip.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))));

    elseif(id_type = 1)then 

        SELECT sum(t.amount) into total
        FROM transactions t
        JOIN additional_charges ac ON ac.transactions_id = t.id
		where  t.modality_transaction_id NOT IN ( 1,2 )
		    and t.status_transaction_id in (1,5)
		    and ca.program_id is null
		    AND t.type_transaction_id NOT IN (3,10,11,14,15,16,17 )
        and (date(t.settlement_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(t.settlement_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))));

	elseif(id_type = 3)then 

        SELECT sum(t.amount) into total
        FROM transactions t
		where t.type_transaction_id = @type_initial
        and t.status_transaction_id in (1,5)
        and (date(t.settlement_date) >= date(concat(date_year,'-01-01')) and (date(t.settlement_date) <= last_day(date(concat(date_year,'-12-01')))));

	elseif(id_type = 4)then 

        SELECT sum(t.amount) into total
        FROM transactions t
		where t.type_transaction_id = @type_others
        and (date(t.settlement_date) >= date(concat(date_year,'-01-01')) and (date(t.settlement_date) <= last_day(date(concat(date_year,'-12-01')))));

    elseif(id_type = 5)then 

        set total = (select case
				when date_month = 1 then sum(p_jan)
                when date_month = 2 then sum(p_feb)
                when date_month = 3 then sum(p_mar)
                when date_month = 4 then sum(p_apr)
                when date_month = 5 then sum(p_may)
                when date_month = 6 then sum(p_jun)
                when date_month = 7 then sum(p_jul)
                when date_month = 8 then sum(p_aug)
                when date_month = 9 then sum(p_sep)
                when date_month = 10 then sum(p_oct)
                when date_month = 11 then sum(p_nov)
                when date_month = 12 then sum(p_dec)
				end
		from generate_report_global_ad
        where year = date_year
        and module_id = 2);

    elseif(id_type = 6)then 

        set total = (select case
				when date_month = 1 then sum(c_jan)
                when date_month = 2 then sum(c_feb)
                when date_month = 3 then sum(c_mar)
                when date_month = 4 then sum(c_apr)
                when date_month = 5 then sum(c_may)
                when date_month = 6 then sum(c_jun)
                when date_month = 7 then sum(c_jul)
                when date_month = 8 then sum(c_aug)
                when date_month = 9 then sum(c_sep)
                when date_month = 10 then sum(c_oct)
                when date_month = 11 then sum(c_nov)
                when date_month = 12 then sum(c_dec)
				end
		from generate_report_global_ad
        where year = date_year
        and module_id = 2);

    elseif(id_type = 7)then 

        set total = (select case
				when date_month = 1 then sum(ifnull(p_jan,0)) + sum(ifnull(c_jan,0))
                when date_month = 2 then sum(ifnull(p_feb,0)) + sum(ifnull(c_feb,0))
                when date_month = 3 then sum(ifnull(p_mar,0)) + sum(ifnull(c_mar,0))
                when date_month = 4 then sum(ifnull(p_apr,0)) + sum(ifnull(c_apr,0))
                when date_month = 5 then sum(ifnull(p_may,0)) + sum(ifnull(c_may,0))
                when date_month = 6 then sum(ifnull(p_jun,0)) + sum(ifnull(c_jun,0))
                when date_month = 7 then sum(ifnull(p_jul,0)) + sum(ifnull(c_jul,0))
                when date_month = 8 then sum(ifnull(p_aug,0)) + sum(ifnull(c_aug,0))
                when date_month = 9 then sum(ifnull(p_sep,0)) + sum(ifnull(c_sep,0))
                when date_month = 10 then sum(ifnull(p_oct,0)) + sum(ifnull(c_oct,0))
                when date_month = 11 then sum(ifnull(p_nov,0)) + sum(ifnull(c_nov,0))
                when date_month = 12 then sum(ifnull(p_dec,0)) + sum(ifnull(c_dec,0))
				end
		from generate_report_global_ad
        where year = date_year
        and module_id = 2);

    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: get_last_payment_ce.sql
DELIMITER $$

CREATE FUNCTION `get_last_payment_ce`(_client_account_id CHAR(36)) RETURNS varchar(255) CHARSET latin1
BEGIN
                    DECLARE last_date datetime;
                    
                    set @type_payment_year = 9;
                    set @type_void = 10;
                    set @type_refund = 11;
                    set @type_zero_payment = 14;
                    set @type_charge_back = 15;
                    set @type_void_parcial=16;
                    set @type_refund_parcial=17;
                    set @modality_return = 6;
                    set @modality_monthly = 1;
                    
                    SELECT MAX(settlement_date)
                    INTO last_date 
                    FROM (
                            
                        SELECT MAX(t.settlement_date) settlement_date  from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.type_transaction_id  NOT IN(@type_payment_year, @type_void, @type_refund, @type_zero_payment, @type_charge_back, @type_void_parcial, @type_refund_parcial)
                        AND t.idchargeback IS NULL
                        
                            UNION ALL
                            
                        SELECT STR_TO_DATE(CONCAT(YEAR(MAX(t.settlement_date)), '-12-31'), '%Y-%m-%d') settlement_date from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.type_transaction_id  = @type_payment_year
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.idchargeback IS NULL
                        
                        UNION ALL
                        
                        SELECT MAX(t.settlement_date) settlement_date from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id  = @type_zero_payment
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.idchargeback IS NULL
                        
                        UNION ALL
                    
                        
                        SELECT null settlement_date
                        FROM partial_refunds_tranctions prt
                        JOIN transactions t on t.transaction_id = prt.transaction_id
                        WHERE t.client_acount_id = _client_account_id
                        AND t.status_transaction_id IN(1,5,8)
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id = @type_refund_parcial
                        
                        UNION ALL
                        
                        
                        SELECT null settlement_date
                        FROM pending_void_transactions pvt
                        JOIN transactions t on t.transaction_id = pvt.transaction_id
                        WHERE t.client_acount_id = _client_account_id
                        AND t.status_transaction_id IN(1,5,8)
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id = @type_void_parcial
                    ) AS monthly_payments;
                
                    RETURN last_date;
                END $$

DELIMITER ;



-- Archivo: get_last_recurring_billing_amount_in_range.sql
DELIMITER $$

CREATE FUNCTION `get_last_recurring_billing_amount_in_range`(p_client_account_id CHAR(36), p_from_date DATE, p_to_date DATE) RETURNS decimal(16,2)
BEGIN
            DECLARE v_last_recurring_billing_amount DECIMAL(16, 2) DEFAULT 0.00;
            SELECT
                CAST(IF(
                        (
                            SELECT
                                CONCAT(rb.monthly_amount, ' / ', rb.created_at) AS valorx
                            FROM
                                recurring_billings rb
                            WHERE
                                client_acount_id = p_client_account_id
                                AND DATE(created_at) BETWEEN p_from_date AND p_to_date
                            ORDER BY
                                created_at DESC
                            LIMIT 1
                        ) IS NULL,
                        (
                            SELECT
                                IFNULL(rb.monthly_amount,0)
                            FROM
                                recurring_billings rb
                            WHERE
                                client_acount_id = p_client_account_id
                                AND DATE(created_at) <= p_to_date
                            ORDER BY
                                created_at DESC
                            LIMIT 1
                        ),
                        (
                            SELECT
                                IFNULL(rb.monthly_amount,0)
                            FROM
                                recurring_billings rb
                            WHERE
                                client_acount_id = p_client_account_id
                                AND DATE(created_at) BETWEEN p_from_date AND p_to_date
                            ORDER BY
                                created_at DESC
                            LIMIT 1
                        )
                ) AS DECIMAL(16, 2))
            INTO v_last_recurring_billing_amount;
            
            RETURN IFNULL( CAST(v_last_recurring_billing_amount AS DECIMAL(16, 2)), 0.00);
        END $$

DELIMITER ;



-- Archivo: get_medium_score.sql
DELIMITER $$

CREATE FUNCTION `get_medium_score`(equ int, exp int, tra int) RETURNS int
begin
	declare total int;
    
	if(equ <> 0 and exp <> 0 and tra <> 0)then
    
		set total = case
			when equ > exp and equ < tra or equ < exp and equ > tra then equ
			when exp > equ and exp < tra or exp < equ and exp > tra then exp
			when tra > equ and tra < exp or tra < equ and tra > exp then tra
			when tra = equ and (tra > exp or tra < exp) then tra
			when equ = exp and (equ > tra or equ < tra) then equ
			when exp = tra and (exp > equ or exp < equ) then exp
			when exp = tra and exp = equ and tra = equ then exp
		end;
        
	else
        if(equ > 0 and exp > 0)then
        
			set total = case
						when equ > exp then exp
                        when equ < exp then equ
						when equ = exp then equ
                        end;
                        
		elseif(exp > 0 and tra > 0)then
        
			set total = case
						when tra > exp then exp
                        when tra < exp then tra
						when tra = exp then tra
                        end;
                        
		elseif(equ > 0 and tra > 0)then
        
			set total = case
						when tra > equ then equ
                        when tra < equ then tra
						when tra = equ then equ
                        end;
                        
		elseif(equ > 0)then
			set total = equ;
            
		elseif(exp > 0)then
			set total = exp;
            
		elseif(tra > 0)then
			set total = tra;
            
        end if;
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: get_monthly_percentage.sql
DELIMITER $$

CREATE FUNCTION `get_monthly_percentage`(id_user int , date_month varchar(4) , date_year varchar(4), modul int) RETURNS decimal(16,2)
BEGIN

 	set @percent = (select sc.percentage_pay
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id
		where   um.main_module = 1
			and um.module_id = modul
			and sc.user_id = id_user
			and date_format(sc.created_at,'%Y-%m') = concat(date_year,'-',date_month) limit 1);


RETURN @percent;

        END $$

DELIMITER ;



-- Archivo: get_months_owed_by_amg_rules.sql
DELIMITER $$

CREATE FUNCTION `get_months_owed_by_amg_rules`(settlement_date date, status_transaction_id int, type_payment int, method_payment int, day_payment int) RETURNS int
BEGIN
            set @validate_current_month = case
            when status_transaction_id is null then false
            ELSE CalculateMonthsOwed(settlement_date) = 0
            end;
            set @validate_one_month = case
                        when status_transaction_id is null then
                            (
                                CalculateMonthsOwed(DATE_ADD(DATE_ADD(DATE(settlement_date), interval 1 month) , INTERVAL -DAY(CURDATE())+1 DAY)) = 1
                            )
                        ELSE CalculateMonthsOwed(settlement_date) = 1
                        end;

                set @validate_two_month = case
                        when status_transaction_id is null then
                            (
                                CalculateMonthsOwed(DATE_ADD(DATE_ADD(DATE(settlement_date), interval 1 month) , INTERVAL -DAY(CURDATE())+1 DAY)) = 2
                            )
                        ELSE CalculateMonthsOwed(settlement_date) = 2
                    end;

                set @approved_pay = (status_transaction_id in (1,5,8) or status_transaction_id is null);
               	set @validate_lp_declined = DATE(settlement_date) BETWEEN DATE(DATE_ADD(concat(if(month(now()) = 01 and day(now()) in (1,2,3,4,5), year(now()) - 1, year(now())),'-', if(day(now()) in (1,2,3,4,5), if(month(now()) - 1 = 0, '12', month(now()) - 1), month(now())),'-','06'),INTERVAL -4 month))
				and DATE(concat(if(month(now()) = 01 and day(now()) in (1,2,3,4,5), year(now()) - 1, year(now())),'-', if(day(now()) in (1,2,3,4,5), if(month(now()) - 1 = 0, '12', month(now()) - 1), month(now())),'-','06'));
                set @is_automatic_payment = method_payment = 0 and type_payment = 0;
                set @is_manual_payment = method_payment = 0 and type_payment = 1;
                set @is_other_payment = method_payment = 1 and (type_payment in (NULL, 2, 0, 1));
               	set @formatted_day = LPAD(day_payment, 2, '0');
                   set @payment_date_major_curr_date = (CURDATE() >= DATE_FORMAT(CONCAT(DATE_FORMAT(if(DAY(now()) < 6, DATE_SUB(CURDATE(), INTERVAL 1 MONTH),CURDATE()), '%Y-%m-'), @formatted_day), '%Y-%m-%d'));
                set @tab = null;
            case

                        when  (@validate_lp_declined = true and @validate_current_month = true
                            and @is_automatic_payment
                            and @payment_date_major_curr_date
                            and @approved_pay)  then   set @tab = 1;



                        when  (@validate_lp_declined = true and @validate_current_month = true
                            and @is_manual_payment
                            and @approved_pay)  then  set @tab = 2;



                        when  (@validate_lp_declined = true and @validate_current_month = true
                            and @is_other_payment
                            and @approved_pay)  then set @tab = 3;



                        when  (@validate_one_month = true
                            and ((@is_automatic_payment and @approved_pay) or @is_manual_payment or @is_other_payment))  then set @tab = 4;


                        when  (@validate_two_month = true
                            and ((@is_automatic_payment and @approved_pay) or @is_manual_payment or @is_other_payment))  then set @tab = 5;
                        else set @tab = 7;
                    END CASE;

                RETURN @tab;
        END $$

DELIMITER ;



-- Archivo: get_myssing_days.sql
DELIMITER $$

CREATE FUNCTION `get_myssing_days`(
        FechaFinal datetime
    ) RETURNS int
BEGIN
    
        DECLARE varfecha DATETIME;
        DECLARE diaslaborales INT;
    
        SET varfecha = now();
        SET diaslaborales = 0;
    
        WHILE (DATE_ADD(FechaFinal, INTERVAL 2 DAY) > varfecha) DO
            IF (DAYOFWEEK(varfecha) NOT IN (1)) THEN
                SET diaslaborales = diaslaborales + 1;
            END IF;
            SET varfecha = DATE_ADD(varfecha, INTERVAL 1 DAY);
        END WHILE;
        SELECT COUNT(*)into @fday FROM usa_holidays as uh    	
        WHERE uh.holiday BETWEEN now() AND date(FechaFinal);
        
        RETURN diaslaborales-@fday-1;
    END $$

DELIMITER ;



-- Archivo: get_negotations_active.sql
DELIMITER $$

CREATE FUNCTION `get_negotations_active`( creditor_id char(100)) RETURNS int
BEGIN
          DECLARE count INT;
          SELECT COUNT(*) INTO count
          FROM offer o
          LEFT JOIN ds_offer_payment_orders dopo ON dopo.offer_id = o.id
          left join offer_payment_fractions opf on opf.offer_id=o.id
          WHERE o.creditor_id = creditor_id AND dopo.payment_order_status_id is not null and date(opf.payment_date)<date(now()) ;
         
          RETURN count;
        END $$

DELIMITER ;



-- Archivo: get_not_working_days_by_schedule_employee_id.sql
DELIMITER $$

CREATE FUNCTION `get_not_working_days_by_schedule_employee_id`(employee_id int, mark_time date) RETURNS int
BEGIN
        DECLARE schedule_justification INT DEFAULT 0;
        select ifnull((SELECT
            CASE
                WHEN COUNT(est.id) = 0 THEN 0
                WHEN est.work_start_time IS NULL AND est.work_end_time IS NULL  and est.employee_id not in(
                select est.employee_id from employees_schedule_tracking est 
                join employees e on e.id=est.employee_id 
                where  est.work_start_time is null and est.work_end_time  is null
                group by(est.employee_id)
                HAVING count(*)>=7)THEN 1
                ELSE 2
                END AS caro
                    FROM
                    employees_schedule_tracking est
                JOIN
                    employees e ON e.id = est.employee_id 
                WHERE
                    est.created_at < mark_time
                    AND DAYOFWEEK(mark_time) = est.day_of_the_week
                    AND e.id_user = employee_id
            GROUP BY
                est.id,
                est.work_start_time,
                est.work_end_time,
                est.created_at order by  est.created_at  desc limit 1),0)into  schedule_justification;
      
      return schedule_justification;
      END $$

DELIMITER ;



-- Archivo: get_number_and_name.sql
DELIMITER $$

CREATE FUNCTION `get_number_and_name`(_number_id INT) RETURNS json
BEGIN
                DECLARE _number VARCHAR(20);
                DECLARE _number_name VARCHAR(250);
                DECLARE result JSON;

                
                IF _number_id IS NOT NULL AND _number_id != 0 THEN
                    SELECT number_format, rc_name
                    INTO _number, _number_name
                    FROM credentials_ring_centrals
                    WHERE id = _number_id;
                    
                    
                    SET result = JSON_OBJECT('number', _number, 'name', _number_name);
                ELSE
                    
                    SET result = NULL;
                END IF;

                RETURN result;
        END $$

DELIMITER ;



-- Archivo: get_numbers_from_module.sql
DELIMITER $$

CREATE FUNCTION `get_numbers_from_module`(module_id INT) RETURNS json
BEGIN
    DECLARE result JSON;
    SET @submodule = IF(module_id = 32, 'CORPORATE', 'PERSONAL') COLLATE utf8mb4_unicode_ci;

    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'id', result_table.id,
            'module_id', result_table.module_id,
            'number_format', result_table.number_format,
            'agent', result_table.agent,
            'agent_id', result_table.agent_id,
            'submodule', result_table.submodule
        )
    ) INTO result
    FROM (
        SELECT 
            crc.id,
            crc.module_id,
            crc.number_format,
            CASE WHEN u.id IS NULL THEN 'SYSTEM' ELSE CONCAT_WS(' ', u.first_name, u.last_name) END AS agent,
            IFNULL(u.id, 0) AS agent_id,
            crc.customer_service_type AS submodule
        FROM 
            credentials_ring_centrals crc
        JOIN 
            users u ON u.id = crc.assigned_to
        JOIN 
            user_module um ON um.user_id = u.id 
            AND um.module_id = module_id
        WHERE 
            crc.assigned_to IS NOT NULL
            AND crc.deleted_at IS NULL
        UNION ALL
        SELECT 
            crc2.id,
            crc2.module_id,
            crc2.number_format,
            CASE WHEN u2.id IS NULL THEN 'SYSTEM' ELSE CONCAT_WS(' ', u2.first_name, u2.last_name) END AS agent,
            IFNULL(u2.id, 0) AS agent_id,
            crc2.customer_service_type AS submodule
        FROM 
            credentials_ring_centrals crc2
        LEFT JOIN 
            users u2 ON crc2.assigned_to = u2.id
        WHERE 
            crc2.customer_service_type = @submodule COLLATE utf8mb4_unicode_ci
            AND crc2.deleted_at IS NULL
    ) AS result_table;

    RETURN result;
END $$

DELIMITER ;



-- Archivo: get_pending_or_done_sales.sql
DELIMITER $$

CREATE FUNCTION `get_pending_or_done_sales`(
            p_year INT,
            p_month INT,
            p_day INT,
            p_program_id INT,
            p_sales_status ENUM('PENDING', 'DONE')
        ) RETURNS int
BEGIN
            
            DECLARE v_total_sales INT DEFAULT 0;
            SELECT
                COUNT(*)
            INTO
                v_total_sales
            FROM sales s
            WHERE ( p_sales_status IS NULL OR ( p_sales_status = 'DONE' AND s.client_id IS NOT NULL ) OR ( p_sales_status = 'PENDING' AND s.client_id IS NULL) )
                AND YEAR(s.created_at) = p_year
                AND ( p_month IS NULL OR MONTH(s.created_at) = p_month )  
                AND ( p_day IS NULL OR DAY(s.created_at) = p_day )
                AND ( p_program_id IS NULL OR s.program_id = p_program_id );
        
            RETURN v_total_sales;
        END $$

DELIMITER ;



-- Archivo: get_route_account.sql
DELIMITER $$

CREATE FUNCTION `get_route_account`(id_account varchar(36)) RETURNS varchar(255) CHARSET latin1
BEGIN
                RETURN (select concat(substr(ca.account,1,2),'/',ca.account ) route 
                        from client_accounts ca 
                        where id = id_account);
            END $$

DELIMITER ;



-- Archivo: get_route_project.sql
DELIMITER $$

CREATE FUNCTION `get_route_project`(project_id int) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
        RETURN (select concat(substr(p.project_code,1,2),'/',p.project_code ) route 
                        from projects p 
                        where id = project_id);
        END $$

DELIMITER ;



-- Archivo: get_route_rounds.sql
DELIMITER $$

CREATE FUNCTION `get_route_rounds`(id_round varchar(36)) RETURNS varchar(255) CHARSET latin1
BEGIN
            RETURN (select concat(case
                when ca.program_id = 1 then 'BU'
                when ca.program_id = 2 then 'BC'
                when ca.program_id = 3 then 'CE'
                when ca.program_id = 4 then 'DS'
                when ca.program_id = 5 then 'TR'
                when ca.program_id = 6 then 'CD'
                when ca.program_id = 7 then 'SP'
                when ca.program_id = 8 then 'KB'
                end ,'/',ca.account) route
                from ncr_round_letters nrl
                    left join ncr_letters nl on nl.id = nrl.ncr_letters_id
                    left join client_accounts ca on ca.id = nl.account_client_id or ca.id = nrl.client_account_id
                where  nrl.id = id_round
            );
        END $$

DELIMITER ;



-- Archivo: get_sales_commission_by_user_id.sql
DELIMITER $$

CREATE FUNCTION `get_sales_commission_by_user_id`(user_id_p int, month_p int, year_p int, module_id_p int) RETURNS decimal(16,2)
BEGIN
            DECLARE total decimal(16,2) default 0;
            DECLARE sum_ce_digital decimal(16,2) default 0;
                           
            SELECT IFNULL(SUM(IFNULL(sc.commission,0) - IFNULL(sc.amount_for_sup,0) - IFNULL(sc.amount_for_ceo,0) - IFNULL(sc.amount_for_assist_sup,0)),0) INTO sum_ce_digital
            FROM sales_commissions sc
            JOIN sales s ON sc.sale_id = s.id AND s.module_id = module_id_p
            WHERE sc.user_id = user_id_p
            AND sc.state = 1
            AND DATE_FORMAT(sc.created_at, "%m") * 1 = month_p
            AND DATE_FORMAT(sc.created_at, "%Y") * 1 = year_p;
                            
            SET total = total + sum_ce_digital;
                            
            SELECT IFNULL(SUM(IFNULL(gcs.amount,0)),0) INTO sum_ce_digital
            FROM general_commissions_supervisors gcs
            WHERE gcs.user_id = user_id_p
            AND DATE_FORMAT(gcs.created_at, "%m") * 1 = month_p
            AND DATE_FORMAT(gcs.created_at, "%Y") * 1 = year_p
            AND gcs.module_id = module_id_p
            AND gcs.status_commission = 1;
                  
            SET total = total + sum_ce_digital;
        
            return( total );
        END $$

DELIMITER ;



-- Archivo: get_sentiment_counter_by_module.sql
DELIMITER $$

CREATE FUNCTION `get_sentiment_counter_by_module`(
            _month INT,
            _year INT,
            _program_id INT,
            _sentiment INT
       ) RETURNS int
BEGIN
           DECLARE _total INT DEFAULT 0;
       
            IF(_program_id = 0) THEN
                
                SET _total = (SELECT COUNT(*)
                                FROM notes n
                                JOIN leads l ON n.lead_id = l.id
                                JOIN modules m ON m.id = l.belongs_module 
                                WHERE n.transcription_status = 3 
                                AND l.belongs_module IS NOT NULL
                                AND n.sentiment IS NOT NULL
                                AND YEAR(n.created_at) = _year
                                AND MONTH(n.created_at) = _month
                                AND n.sentiment = _sentiment);
            ELSE
                SET _total = (SELECT 
                                COUNT(*)
                                FROM notes_accounts na
                                JOIN client_accounts ca ON na.client_account_id = ca.id
                                JOIN programs p ON ca.program_id = p.id
                                
                                WHERE na.transcription_status = 3 
                                AND na.sentiment IS NOT NULL
                                AND na.`type` IN (1,10)
                                AND YEAR(na.created_at) = _year
                                AND MONTH(na.created_at) = _month
                                AND p.id = _program_id
                                AND na.sentiment = _sentiment);
            END IF;
            
            RETURN _total;
        END $$

DELIMITER ;



-- Archivo: get_total_charge_in_payment_schedule.sql
DELIMITER $$

CREATE FUNCTION `get_total_charge_in_payment_schedule`(_payment_schedule_id BIGINT) RETURNS decimal(18,2)
BEGIN
			DECLARE total_charge DECIMAL(18, 2);
           	set @type_void = 10;
           	set @type_refund = 11;
        
           	SELECT COALESCE(SUM(amount), 0) 
           	INTO total_charge
			FROM (
			    SELECT DISTINCT
			        cs.charge_id,
			        CASE
			            WHEN ac.charge_indicator = 1 THEN (ac.amount - t.amount) -
			                (
			                	
			                	SELECT COALESCE(SUM(ac2.amount),0) FROM additional_charges ac2 
			                	JOIN transactions t2 ON t2.id = ac2.transactions_id
			                	WHERE ac2.partial_group = ac.id
			                	AND t2.status_transaction_id IN(1,5,8) 
				                AND ac2.state_charge = 1
				                AND t2.type_transaction_id NOT IN(@type_void, @type_refund)
			                )
			            ELSE ac.amount
			        END AS amount
			    FROM charge_schedules cs
			    JOIN additional_charges ac ON ac.id = cs.charge_id
			    JOIN transactions t ON t.id = ac.transactions_id
			    WHERE cs.payment_schedule_id = _payment_schedule_id
			    AND t.status_transaction_id IN (1, 5, 8)
			    AND ac.state_charge = 1
			    AND t.type_transaction_id NOT IN(@type_void, @type_refund)
			    AND ac.partial_group IS NULL
			    AND ac.idcreditor IS NULL
			
			    UNION ALL
			
			    SELECT DISTINCT cs.charge_id, ac.amount
			    FROM charge_schedules cs
			    JOIN additional_charges ac ON ac.id = cs.charge_id
			    WHERE cs.payment_schedule_id = _payment_schedule_id
			    AND ac.transactions_id IS NULL
			    AND ac.from_op = 0 
			    AND ac.state_charge = 1
			    AND ac.idcreditor IS NULL
			) AS total_charges;
                
            RETURN total_charge;
        END $$

DELIMITER ;



-- Archivo: get_total_payments_and_last_date_in_payment_schedule.sql
DELIMITER $$

CREATE FUNCTION `get_total_payments_and_last_date_in_payment_schedule`(_client_account_id CHAR(36)) RETURNS varchar(255) CHARSET latin1
BEGIN
                    DECLARE total_payments DECIMAL(18,2);
                    DECLARE last_date datetime;
                    DECLARE id_sale INT;
                    
                    set @type_payment_year = 9;
                    set @type_void = 10;
                    set @type_refund = 11;
                    set @type_zero_payment = 14;
                    set @type_charge_back = 15;
                    set @type_void_parcial=16;
                    set @type_refund_parcial=17;
                    set @modality_return = 6;
                    set @modality_monthly = 1;
                       set @modality_initial = 2;
                      set @type_initial = 3;
                    
                    SELECT COALESCE(SUM(amount),0), MAX(settlement_date)
                    INTO total_payments, last_date 
                    FROM (
                            
                        SELECT COALESCE(SUM(t.amount),0) amount, MAX(t.settlement_date) settlement_date  from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.type_transaction_id  NOT IN(@type_payment_year, @type_void, @type_refund, @type_zero_payment, @type_charge_back, @type_void_parcial, @type_refund_parcial)
                        AND t.idchargeback IS NULL
                        
                            UNION ALL
                            
                        SELECT COALESCE(SUM(t.amount),0) amount, STR_TO_DATE(CONCAT(YEAR(MAX(t.settlement_date)), '-12-31'), '%Y-%m-%d') settlement_date from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.type_transaction_id  = @type_payment_year
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.idchargeback IS NULL
                        
                        UNION ALL
                        
                        SELECT 0 amount, MAX(t.settlement_date) settlement_date from transactions t 
                        where t.client_acount_id = _client_account_id
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id  = @type_zero_payment
                        AND t.status_transaction_id IN (5,8,1)
                        AND t.idchargeback IS NULL
                        
                        UNION ALL
                    
                        
                        SELECT -1 * COALESCE(SUM(t.amount),0) AS amount, null settlement_date
                        FROM partial_refunds_tranctions prt
                        JOIN transactions t on t.transaction_id = prt.transaction_id
                        WHERE t.client_acount_id = _client_account_id
                        AND t.status_transaction_id IN(1,5,8)
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id = @type_refund_parcial
                        
                        UNION ALL
                        
                        
                        SELECT -1 * COALESCE(SUM(t.amount),0) AS amount, null settlement_date
                        FROM pending_void_transactions pvt
                        JOIN transactions t on t.transaction_id = pvt.transaction_id
                        WHERE t.client_acount_id = _client_account_id
                        AND t.status_transaction_id IN(1,5,8)
                        AND t.modality_transaction_id = @modality_monthly
                        AND t.type_transaction_id = @type_void_parcial
                    ) AS monthly_payments;
                   
                       IF last_date IS NULL THEN
                               
                            SELECT ip.sale_id INTO id_sale FROM client_accounts ca
                            inner join initial_payments ip on ip.account = ca.account
                            where ca.id = _client_account_id;
                   
                            select ip.created_at INTO last_date  
                            from initial_payments ip
                            WHERE ip.sale_id = id_sale;
                    END IF;
                   
                   IF last_date IS NULL THEN
                           
                           select t.settlement_date  into last_date from transactions t 
                          where t.client_acount_id = _client_account_id and t.idchargeback is null
                          and t.type_transaction_id = @type_initial and t.modality_transaction_id = @modality_initial 
                         and t.status_transaction_id in (1,5, 8) limit 1;
                   END IF;
                
                    RETURN CONCAT(ifnull(total_payments,0), ',', ifnull(last_date, DATE_SUB(CURDATE(), INTERVAL 1 MONTH)));
                END $$

DELIMITER ;



-- Archivo: get_total_remuneration.sql
DELIMITER $$

CREATE FUNCTION `get_total_remuneration`(
            _employee_id varchar(255),
            _month int,
            _year int
        ) RETURNS decimal(10,2)
begin
            declare v_total_remuneration decimal(10,2) default 2000;
            declare v_missing_hours int default 0;
            declare v_missing_hours_discount decimal(10,2) default 0;
            declare error_message text default 'error';
            declare salary decimal(10,2) default 0;
            declare pension_fund JSON;
            declare pension_fund_type varchar(255);
            declare afp_contribution decimal(10,2) default 0;
            declare afp_comissions decimal(10,2) default 0;
            declare afp_insurance decimal(10,2) default 0;
            declare onp_contribution decimal(10,2) default 0;
            declare _id_user int;
            declare _fifth_category decimal(10,2) default 0;

                SELECT get_employee_salary(_employee_id,_month,_year) INTO salary;

                    if salary< 0 then
                    set error_message='error: salary not found or lower than 0';
                    signal sqlstate '45000' set message_text=error_message;
                    end if;
                    SELECT calculate_contributions_pension_fund(_employee_id,_month,_year) INTO  pension_fund;
                    select pf.`type` from employees e inner join pension_fund pf on pf.id=e.pension_fund_id where e.id=_employee_id into pension_fund_type;
                    set onp_contribution = JSON_EXTRACT(pension_fund, '$.ONP_CONTRIBUTION');
                    set afp_insurance = JSON_EXTRACT(pension_fund, '$.AFP_INSURANCE');
                    set afp_comissions = JSON_EXTRACT(pension_fund, '$.AFP_COMISSIONS');
                    set afp_contribution = JSON_EXTRACT(pension_fund, '$.AFP_CONTRIBUTION');
                    select id_user from employees where id=_employee_id  and id_user is not null into _id_user;
                    select thw.total_hours_not_worked  INTO v_missing_hours from total_hours_worked thw
                    WHERE thw.user_id = _id_user
                    and thw.year=_year and thw.month=_month and thw.updated_at is null;
                    select get_hours_discount(_employee_id,v_missing_hours,_month,_year) into v_missing_hours_discount;
                    select fifth_category_calculation(_employee_id,_month,_year) into _fifth_category;
                    if
                    pension_fund_type='private' then
                    set v_total_remuneration = salary - (afp_contribution + afp_comissions + afp_insurance + v_missing_hours_discount+_fifth_category);
                    else
                    set v_total_remuneration = salary -( onp_contribution + v_missing_hours_discount+_fifth_category);

                    end if;
                    return cast(v_total_remuneration as decimal(10,2)) ;
        end $$

DELIMITER ;



-- Archivo: get_type_card.sql
DELIMITER $$

CREATE FUNCTION `get_type_card`(cardnumber char(255)) RETURNS varchar(2) CHARSET latin1
BEGIN
			declare type_card char(2) default null;
    
			if(cardnumber is not null)then
				IF SUBSTRING(cardnumber, 1, 1) NOT REGEXP '^[0-9]+$' THEN
					
					SET type_card = 'X';
				ELSE
					set type_card = case
						when SUBSTRING(cardnumber, 1, 2) IN ('34', '37') then 'A'
						when SUBSTRING(cardnumber, 1, 1) IN ('4') then 'V'
						when SUBSTRING(cardnumber, 1, 2) IN ('60', '62', '64', '65') then 'D'
						when SUBSTRING(cardnumber, 1, 2) IN ('30', '35') then 'J'
						when SUBSTRING(cardnumber, 1, 2) IN ('36', '38') then 'DI'
						when SUBSTRING(cardnumber, 1, 2) IN ('51', '52', '53', '54', '55', '22', '23', '24', '25', '26', '27') then 'M'
						else 'X'
					end;
				END IF;
			end if;
			
		RETURN type_card;
		END $$

DELIMITER ;



-- Archivo: health_insurance_contribution_calculation.sql
DELIMITER $$

CREATE FUNCTION `health_insurance_contribution_calculation`( _employee_id VARCHAR(255), _month int,_year int) RETURNS json
BEGIN

        DECLARE _employee_contributions JSON;
        DECLARE _real_salary DECIMAL(8, 2);

        DECLARE _essalud_contribution INT;
        DECLARE _sis_contribution DECIMAL(8,2) DEFAULT 30;
       	DECLARE _sis_contribution_by_the_state INT;
        DECLARE _sis_contribution_by_the_company INT;


       	SELECT JSON_EXTRACT(base_salary_bonification_calculation(_employee_id, _month, _year),'$.base_salary') INTO @base_salary;
       	SELECT ifnull(get_employee_salary(_employee_id, _month, _year),0) INTO _real_salary;

       	SELECT `value` INTO _essalud_contribution FROM payment_settings WHERE slug = 'ECP' and updated_by is null and updated_at is null;

		SELECT `value` INTO _sis_contribution FROM payment_settings WHERE slug = 'SCA' and updated_by is null and updated_at is null;

		SELECT `value` INTO _sis_contribution_by_the_state FROM payment_settings WHERE slug = 'SCBSP' and updated_by is null and updated_at is null;

		SELECT `value` INTO _sis_contribution_by_the_company FROM payment_settings WHERE slug = 'SCBCP' and updated_by is null and updated_at is null;

        RETURN JSON_OBJECT(
            'essalud_contribution', CAST( @base_salary * ( _essalud_contribution / 100 ) AS DECIMAL(10,2) ),
            'sis_total_contribution_cost', CAST(_sis_contribution AS DECIMAL(10,2) ) ,
            'sis_contribution_by_the_state', CAST( _sis_contribution * ( _sis_contribution_by_the_state / 100 ) AS DECIMAL(10,2) ),
            'sis_contribution_by_the_company', CAST( _sis_contribution * ( _sis_contribution_by_the_company / 100 ) AS DECIMAL(10,2) )
	    );
        END $$

DELIMITER ;



-- Archivo: isInThePaymentPeriod.sql
DELIMITER $$

CREATE FUNCTION `isInThePaymentPeriod`(settlement_date date, target_date date) RETURNS int
BEGIN 
                declare isInPeriod int;
                set @datem = DATE(concat(year(target_date), '-', month(target_date), '-01'));
                select DATE(settlement_date) between @datem and last_day(@datem) into isInPeriod;
                return isInPeriod;
            END $$

DELIMITER ;



-- Archivo: is_client_debtor.sql
DELIMITER $$

CREATE FUNCTION `is_client_debtor`(_id char(36)) RETURNS int
BEGIN
            set @is_debtor = 0;
            set @total_payment = 0;
            set @payment = 0;
            set @beforeMonth = MONTH(DATE_ADD(NOW(), INTERVAL -1 MONTH));
            set @beforeYear = if(@beforeMonth = 12, year(NOW())-1, year(now()));

            select if(total_payment(ca.id) - (calculate_max_payment_or_remaining_amount_ds(ca.id) + total_charge(ca.id)) >= 0 , 1 , 0 ) as total_payment , 
                case 
                    when program_date_for_new_range(4 , max(settlement_date)) then max(t.settlement_date) >= concat(@beforeYear,'-',@beforeMonth,'-01')
                    else if(day(now()) >= 6 ,
                                max(t.settlement_date) >= concat(year(now()),'-',@beforeMonth,'-06') ,
                                max(t.settlement_date) >= date_add(concat(year(now()),'-',@beforeMonth,'-06') , interval -1 month )
                        ) 
                    end  payment
                into @total_payment , @payment
            from transactions t
            join client_accounts ca on t.client_acount_id = ca.id 
            where ca.id = _id and status_transaction_id in (1,5) and not t.type_transaction_id  in (8,14,16,17)
            group by 1;
            return if( @total_payment = 1 , 0 , if(@payment = 1 , 0 , 1) );
        END $$

DELIMITER ;



-- Archivo: is_debtor.sql
DELIMITER $$

CREATE FUNCTION `is_debtor`(_client_account_id varchar(36), _month int, _year int) RETURNS tinyint(1)
BEGIN
            declare method_payment tinyint;
            declare type_payment tinyint;
            declare payment_days int;
            declare type_payment_client tinyint; 
            declare id_transaction_month varchar(36) default null;
            declare date_transaction date;
            declare is_current_time boolean default false;
            declare client_is_debtor boolean default false;
            declare is_over_payment_day boolean default false;
            declare is_still_last_month boolean default false;
            declare last_month_date date;
            declare date_start_month_previous_month date;
            declare date_end_month_previous_month date;
            declare date_start_month date;
            declare date_end_month date;

            set @type_automatic = 1;
            set @type_manual = 2;
            set @type_zero = 14;
            set @type_initial = 3;
            set @method_card = 1;
            set @modality_initial =2;

        
            
            set last_month_date = DATE_SUB(NOW(), INTERVAL 1 MONTH);
        
            
            
            set date_start_month = DATE(CONCAT(_year, '-', _month, '-', 01));
            set date_end_month_previous_month = DATE_ADD(date_start_month, interval -1 day);
            
            set date_start_month_previous_month = DATE_SUB(date_start_month, interval 1 month);
            set date_end_month = DATE(DATE_ADD(date_end_month_previous_month, interval 1 MONTH)) ;
        
            
            if (month(now()) = _month and year(now()) = _year) then
                set is_current_time = true;
            end if;
            
            
            select rb.method_payment, rb.type_payment, rb.day_payment into method_payment, type_payment, payment_days
            from recurring_billings rb where rb.updated_at is null 
            and rb.client_acount_id = _client_account_id;
        
            
            if (MONTH(last_month_date) = _month and year(last_month_date) = _year and day(now()) in (1,2,3,4,5)) then 
                set is_still_last_month = true;
            end if;
        
            
            
            CASE
                WHEN method_payment = 0 and type_payment = 0
                    THEN SET type_payment_client = 1; 
                WHEN method_payment = 0 and type_payment = 1
                    THEN SET type_payment_client = 2; 
                WHEN method_payment = 1 
                    THEN SET type_payment_client = 3; 
            END CASE;
           
            
            select id, t.settlement_date into id_transaction_month, date_transaction
               from transactions t 
               where t.settlement_date 
               between date_start_month_previous_month
               and date_end_month
               AND t.type_transaction_id IN (@type_automatic, @type_manual, @type_zero, @type_initial)
                AND (t.type_transaction_id != @type_initial OR 
                    (t.type_transaction_id = @type_initial AND 
                    t.modality_transaction_id = @modality_initial AND 
                    t.method_transaction_id = @method_card))
                AND t.status_transaction_id IN (1, 5)
               and t.status_transaction_id in (1,5)
               and t.client_acount_id = _client_account_id
               order by t.settlement_date desc
               limit 1;
           
               case
                   when type_payment_client = 1 
                   then 
                    set is_over_payment_day = is_current_time;
                    
                    
                
                    
                    if (date_transaction between date_start_month and date_end_month) THEN
                        return false;
                    end if;
                    
                    if (date_transaction is null) then
                        return true;
                    end if;
                    
                    
                    if (date_transaction between date_start_month_previous_month and date_end_month_previous_month) then
                        
                        if (is_over_payment_day = true) then 
                            return true;
                        else
                            return false;
                        end if;
                    end if;
            
                      
                   when type_payment_client in (2,3)
                    
                   then 
                       
                    if (date_transaction is null or date_transaction not between date_start_month and date_end_month) THEN
                        set client_is_debtor = true;
                    end if;
               end case;
        
            return client_is_debtor;
        END $$

DELIMITER ;



-- Archivo: is_numeric.sql
DELIMITER $$

CREATE FUNCTION `is_numeric`(item varchar(1024)) RETURNS int
begin
declare total int;
	if(item REGEXP '^[+-]?[0-9]*([0-9]\.|[0-9]|\.[0-9])[0-9]*(e[+-]?[0-9]+)?$')then
		set  total = item;
	else
		set total = 0;
	end if;
return total;
end $$

DELIMITER ;



-- Archivo: json_clients_status_performance_ce.sql
DELIMITER $$

CREATE FUNCTION `json_clients_status_performance_ce`(id_user int, t_status int,t_year int,t_month int, t_program_id int) RETURNS json
begin   
                declare x int default 0;
                drop temporary table if exists j_clients;
                create temporary table j_clients (
                        client_account_id char(36),
                        status_performance_id int
                ) ENGINE=MyISAM;
                        insert into j_clients (client_account_id, status_performance_id)
                        select distinct aah.client_acount_id `client_acount_id` , x.status_performance_id from client_accounts ca 
                                join accounts_advisors_histories aah on aah.client_acount_id = ca.id and ((aah.advisor_id = id_user) and date(aah.created_at) <= DATE_ADD(concat(t_year,'-',t_month,'-06'), INTERVAL 1 month) and (aah.updated_at is null or not aah.updated_at < DATE_ADD(concat(t_year,'-',t_month,'-05'),interval 1 month) ))
                               left join (select tbl2.client_account_id, max(tbl2.created_at) `created_at` , tbl2.status_performance_id status_performance_id
                                        from
                                        (
                                        select client_account_id, max(created_at) as `created_at`
                                        from tracking_status_clients_advisor_performance_ce where created_at  between concat(t_year,'-',t_month,'-06') and  DATE_ADD(concat(t_year,'-',t_month,'-06') ,interval 1 month)  
                                        group by client_account_id
                                        ) tbl1
                                        inner join tracking_status_clients_advisor_performance_ce tbl2 on tbl2.client_account_id = tbl1.client_account_id and tbl2.created_at = tbl1.created_at
                                        group by tbl2.client_account_id, tbl2.created_at, tbl2.status_performance_id) x on x.client_account_id = aah.client_acount_id and x.status_performance_id = t_status 
                             where ca.status =1  and ca.program_id = t_program_id;
                             
                             set @json_clients = (select json_arrayagg(JSON_OBJECT('caid',client_account_id,'status_performance_id', status_performance_id)) from j_clients where status_performance_id = t_status);
                                   
                              if(JSON_LENGTH(@json_clients) > 0)then
                              
                                  return @json_clients;
                              
                              else 
                              
                                  return '{}';
                              
                              end if;
              end $$

DELIMITER ;



-- Archivo: json_monthly_report_advisor_performance.sql
DELIMITER $$

CREATE FUNCTION `json_monthly_report_advisor_performance`(t_year int,  t_month int) RETURNS json
begin
            return (select json_arrayagg(JSON_OBJECT('advisor_id',u.id,'clients',count_clients_advisor_ce(u.id,t_year,t_month),'c_current',count_clients_status_performance_ce(u.id,1,t_year,t_month) ,
                        'c_check',count_clients_status_performance_ce(u.id,2,t_year,t_month),'c_urgent',count_clients_status_performance_ce(u.id,3,t_year,t_month),
                        'contac',IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month)) * 100)),2),0),
                        'payments',	(SELECT case
                                    when t_month = 1 then ifnull(ROUND((payment_account_active(concat(t_year,'-','01-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-01-05'),3,u.id) = 0,1,account_active(concat(t_year,'-01-05'),3,u.id)) * 100),2),0)
                                    when t_month = 2 then ifnull(ROUND((payment_account_active(concat(t_year,'-','02-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-02-05'),3,u.id) = 0,1,account_active(concat(t_year,'-02-05'),3,u.id)) * 100),2),0) 
                                    when t_month = 3 then ifnull(ROUND((payment_account_active(concat(t_year,'-','03-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-03-05'),3,u.id) = 0,1,account_active(concat(t_year,'-03-05'),3,u.id)) * 100),2),0)
                                    when t_month = 4 then ifnull(ROUND((payment_account_active(concat(t_year,'-','04-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-04-05'),3,u.id) = 0,1,account_active(concat(t_year,'-04-05'),3,u.id)) * 100),2),0) 
                                    when t_month = 5 then ifnull(ROUND((payment_account_active(concat(t_year,'-','05-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-05-05'),3,u.id) = 0,1,account_active(concat(t_year,'-05-05'),3,u.id)) * 100),2),0)
                                    when t_month = 6 then ifnull(ROUND((payment_account_active(concat(t_year,'-','06-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-06-05'),3,u.id) = 0,1,account_active(concat(t_year,'-06-05'),3,u.id)) * 100),2),0)
                                    when t_month = 7 then ifnull(ROUND((payment_account_active(concat(t_year,'-','07-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-07-05'),3,u.id) = 0,1,account_active(concat(t_year,'-07-05'),3,u.id)) * 100),2),0)
                                    when t_month = 8 then ifnull(ROUND((payment_account_active(concat(t_year,'-','08-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-08-05'),3,u.id) = 0,1,account_active(concat(t_year,'-08-05'),3,u.id)) * 100),2),0)
                                    when t_month = 9 then ifnull(ROUND((payment_account_active(concat(t_year,'-','09-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-09-05'),3,u.id) = 0,1,account_active(concat(t_year,'-09-05'),3,u.id)) * 100),2),0)
                                    when t_month = 10 then ifnull(ROUND((payment_account_active(concat(t_year,'-','10-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-10-05'),3,u.id) = 0,1,account_active(concat(t_year,'-10-05'),3,u.id)) * 100),2),0)
                                    when t_month = 11 then ifnull(ROUND((payment_account_active(concat(t_year,'-','11-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-11-05'),3,u.id) = 0,1,account_active(concat(t_year,'-11-05'),3,u.id)) * 100),2),0)
                                    when t_month = 12 then ifnull(ROUND((payment_account_active(concat(t_year,'-','12-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-12-05'),3,u.id) = 0,1,account_active(concat(t_year,'-12-05'),3,u.id)) * 100),2),0)
                                    end ),
                                'average',ifnull((SELECT case
                                                            when t_month = 1 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-01-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-01-05'),3,u.id) = 0,1,account_active(concat(t_year,'-01-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 2 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-02-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-02-05'),3,u.id) = 0,1,account_active(concat(t_year,'-02-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 3 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-03-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-03-05'),3,u.id) = 0,1,account_active(concat(t_year,'-03-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 4 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-04-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-04-05'),3,u.id) = 0,1,account_active(concat(t_year,'-04-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 5 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-05-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-05-05'),3,u.id) = 0,1,account_active(concat(t_year,'-05-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 6 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-06-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-06-05'),3,u.id) = 0,1,account_active(concat(t_year,'-06-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 7 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-07-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-07-05'),3,u.id) = 0,1,account_active(concat(t_year,'-07-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 8 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-08-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-08-05'),3,u.id) = 0,1,account_active(concat(t_year,'-08-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 9 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-09-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-09-05'),3,u.id) = 0,1,account_active(concat(t_year,'-09-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 10 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-10-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-10-05'),3,u.id) = 0,1,account_active(concat(t_year,'-10-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 11 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-11-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-11-05'),3,u.id) = 0,1,account_active(concat(t_year,'-11-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            when t_month = 12 then ifnull(((IFNULL(ROUND(((JSON_LENGTH(count_clients_status_performance_ce(u.id,1,t_year,t_month)) / if(count_clients_advisor_ce(u.id,t_year,t_month) = 0,1,count_clients_advisor_ce(u.id,t_year,t_month))) * 100),2),0) + Ifnull(ROUND(((payment_account_active(concat(t_year,'-12-05'),3,u.id,null,1) / if(account_active(concat(t_year,'-12-05'),3,u.id) = 0,1,account_active(concat(t_year,'-12-05'),3,u.id))) * 100),2),0)) / 2 ),0)
                                                            end 
                            FROM payment_reports 
                            where (advisor_id = u.id )
                                and (program_id = 3 )
                                and `year` = t_year),0.00),'year',t_year,'month',t_month))
                from users u
                    join user_module um on um.user_id = u.id and module_id = 6
                where um.role_id in(3,2) 
                and u.status = 1);
        END $$

DELIMITER ;



-- Archivo: man_correlative_transaction_id.sql
DELIMITER $$

CREATE FUNCTION `man_correlative_transaction_id`(idprogram int) RETURNS varchar(25) CHARSET latin1
begin
            declare text_program varchar(25);

                select case when idprogram = 1 then 'CBTRBU'
                            when idprogram = 2 then 'CBTRBC'
                            when idprogram = 3 then 'CBTRCE'
                            when idprogram = 4 then 'CBTRDS'
                            when idprogram = 5 then 'CBTRTR'
                            when idprogram = 6 then 'CBTRCD'
                            when idprogram = 7 then 'CBTRSP'
                            when idprogram = 8 then 'CBTRBK'
                            else 'CBTROP' end into text_program;

                set @t_count = (select ifnull(count(*),0) from transactions where substring(transaction_id,1,6) = text_program);


                set @c_transaction = (@t_count + 1);

            set @correlative = (select case
                    when @c_transaction between 0 and  9 then concat(text_program,'00000',@c_transaction)
                    when @c_transaction between 10 and  99  then concat(text_program,'0000',@c_transaction)
                    when @c_transaction between 100 and  999  then concat(text_program,'000',@c_transaction)
                    when @c_transaction between 1000 and  9999  then concat(text_program,'00',@c_transaction)
                    when @c_transaction between 10000 and  99999  then concat(text_program,'0',@c_transaction)
                    when @c_transaction between 100000 and  999999  then concat(text_program,@c_transaction)
                end);

            return @correlative;

        end $$

DELIMITER ;



-- Archivo: man_correlative_transaction_id_paid_amg.sql
DELIMITER $$

CREATE FUNCTION `man_correlative_transaction_id_paid_amg`(idprogram int) RETURNS varchar(25) CHARSET latin1
begin
                    declare text_program varchar(25);

                        select case when idprogram = 1 then 'CBAMGPDBU'
                                    when idprogram = 2 then 'CBAMGPDBC'
                                    when idprogram = 3 then 'CBAMGPDCE'
                                    when idprogram = 4 then 'CBAMGPDDS'
                                    when idprogram = 5 then 'CBAMGPDTR'
                                    when idprogram = 6 then 'CBAMGPDCD'
                                    when idprogram = 7 then 'CBAMGPDSP'
                                    when idprogram = 8 then 'CBAMGPDBK'
                                    else 'CBAMGPDOP' end into text_program;



                        set @t_count = (select ifnull(count(*),0) from transactions where substring(transaction_id,1,7) = text_program);


                        set @c_transaction = (@t_count + 1);

                    set @correlative = (select case
                            when @c_transaction between 0 and  9 then concat(text_program,'00000',@c_transaction)
                            when @c_transaction between 10 and  99  then concat(text_program,'0000',@c_transaction)
                            when @c_transaction between 100 and  999  then concat(text_program,'000',@c_transaction)
                            when @c_transaction between 1000 and  9999  then concat(text_program,'00',@c_transaction)
                            when @c_transaction between 10000 and  99999  then concat(text_program,'0',@c_transaction)
                            when @c_transaction between 100000 and  999999  then concat(text_program,@c_transaction)
                        end);

                    return @correlative;

        END $$

DELIMITER ;



-- Archivo: man_correlative_transaction_id_penalty.sql
DELIMITER $$

CREATE FUNCTION `man_correlative_transaction_id_penalty`(idprogram int) RETURNS varchar(25) CHARSET latin1
begin
            declare text_program varchar(25);

                select case when idprogram = 1 then 'CBPEBU'
                            when idprogram = 2 then 'CBPEBC'
                            when idprogram = 3 then 'CBPECE'
                            when idprogram = 4 then 'CBPEDS'
                            when idprogram = 5 then 'CBPETR'
                            when idprogram = 6 then 'CBPECD'
                            when idprogram = 7 then 'CBPESP'
                            when idprogram = 8 then 'CBPEBK'
                            else 'CBPEOP' end into text_program;

                set @t_count = (select ifnull(count(*),0) from transactions where substring(transaction_id,1,6) = text_program);


                set @c_transaction = (@t_count + 1);

            set @correlative = (select case
                    when @c_transaction between 0 and  9 then concat(text_program,'00000',@c_transaction)
                    when @c_transaction between 10 and  99  then concat(text_program,'0000',@c_transaction)
                    when @c_transaction between 100 and  999  then concat(text_program,'000',@c_transaction)
                    when @c_transaction between 1000 and  9999  then concat(text_program,'00',@c_transaction)
                    when @c_transaction between 10000 and  99999  then concat(text_program,'0',@c_transaction)
                    when @c_transaction between 100000 and  999999  then concat(text_program,@c_transaction)
                end);

            return @correlative;

        end $$

DELIMITER ;



-- Archivo: man_correlative_transaction_id_responsable.sql
DELIMITER $$

CREATE FUNCTION `man_correlative_transaction_id_responsable`(idprogram int) RETURNS varchar(25) CHARSET latin1
begin
            declare text_program varchar(7);
            
                select case when idprogram = 1 then 'CBAMGBU' 
                            when idprogram = 2 then 'CBAMGBC' 
                            when idprogram = 3 then 'CBAMGCE' 
                            when idprogram = 4 then 'CBAMGDS'
                            when idprogram = 5 then 'CBAMGTR'
                            when idprogram = 6 then 'CBAMGCD'
                            when idprogram = 7 then 'CBAMGSP'
                            when idprogram = 8 then 'CBAMGBK'
                            else 'CBAMGOP' end into text_program;
                        
                        
            
                set @t_count = (select ifnull(count(*),0) from transactions where substring(transaction_id,1,7) = text_program);
            
                                    
                set @c_transaction = (@t_count + 1);
            
            set @correlative = (select case 
                    when @c_transaction between 0 and  9 then concat(text_program,'00000',@c_transaction) 
                    when @c_transaction between 10 and  99  then concat(text_program,'0000',@c_transaction)
                    when @c_transaction between 100 and  999  then concat(text_program,'000',@c_transaction)
                    when @c_transaction between 1000 and  9999  then concat(text_program,'00',@c_transaction)
                    when @c_transaction between 10000 and  99999  then concat(text_program,'0',@c_transaction)
                    when @c_transaction between 100000 and  999999  then concat(text_program,@c_transaction)
                end);
            
            return @correlative;
            
        end $$

DELIMITER ;



-- Archivo: ncr_leads_type_card.sql
DELIMITER $$

CREATE FUNCTION `ncr_leads_type_card`(
            type_card int,
            borrowed_card int
        ) RETURNS varchar(255) CHARSET utf8mb3
begin
            declare text_result varchar(255);
        
            set text_result = case
                                when type_card = 1 then 'Client'
                                when type_card = 2 and borrowed_card = 1 then 'AMG'
                                when type_card = 2 and borrowed_card = 2 then 'CRM'
                            end;
                        
            return text_result;
        END $$

DELIMITER ;



-- Archivo: new_account_active.sql
DELIMITER $$

CREATE FUNCTION `new_account_active`(datem date, id_program int, id_advisor int) RETURNS int
BEGIN
				SET @type_automatic = 1;
	            SET @type_manual = 2;
	            SET @type_others = 6;
	            SET @method_cashier = 7;
	            SET @modality_monthly = 1;
	            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-01');
	            SET @last_day_of_month = date_add(@first_day_of_month,interval 1 month); 
	        
	            SET @count_CE_program = 0; 
	            SET @count_other_programs = 0;
	            SET @C_PARAGON_PROGRAM = 9;
	            set @isNotProgramId = (id_program is null) or (id_program = 0);
				
	            SET @new_range = program_date_for_new_range(id_program, @first_day_of_month);
				
				if(@new_range) then
	                select count(distinct ca.id) into @count_CE_program
	                        from client_accounts ca 
	                            inner join accounts_status_histories ash on ash.client_acount_id = ca.id
	                            left join accounts_advisors_histories aah on aah.client_acount_id = ca.id
	                            left join transactions t on t.client_acount_id = ca.id and t.status_transaction_id in (1,5,8)
	                            and (t.type_transaction_id in (@type_automatic,@type_manual) OR
	                                (t.type_transaction_id = @type_manual and t.method_transaction_id not in (@method_cashier)) OR
	                                (t.type_transaction_id = @type_others and t.modality_transaction_id = @modality_monthly) 
	                                )
	                            and t.settlement_date >= @first_day_of_month and t.settlement_date < @last_day_of_month
	                        where date(ca.created_at) < @first_day_of_month 
	                            and (( id_advisor is null or id_advisor = 0 or aah.advisor_id = id_advisor )
													and if( ca.program_id = 3 , true ,
														 date(aah.created_at) <= @last_day_of_month and (aah.updated_at is null or not aah.updated_at <= @last_day_of_month ) )
												)  
	                                    and (ca.program_id = id_program or @isNotProgramId)
	                                    AND ( ca.program_id NOT IN ( @C_PARAGON_PROGRAM ) ) 
	                                    AND program_date_for_new_range(ca.program_id, @first_day_of_month)
	                            and ca.migrating = 0 and (date(ca.created_at)<@first_day_of_month or new_account_paid(ca.id,@first_day_of_month))
	                            and (
	                                ( (ash.status in (1,8,9,10) and date(ash.created_at) < @last_day_of_month) or
	                                    (ash.status in (5,11,12,13) and ash.created_at >= @first_day_of_month and ash.created_at < @last_day_of_month and t.id is not null) )
	                                    and (ash.updated_at is null
	                                            or not ash.updated_at < @last_day_of_month ));  
	            end if;	                                       
	        
	            if(! @new_range or @isNotProgramId)then 
	                    select account_active(datem,id_program,id_advisor) into @count_other_programs ; 
	            end if;
	            RETURN @count_CE_program + @count_other_programs;
            END $$

DELIMITER ;



-- Archivo: new_account_paid.sql
DELIMITER $$

CREATE FUNCTION `new_account_paid`(id_account varchar(36),datem date) RETURNS int
BEGIN
            SET @type_automatic := 1;
            SET @type_manual := 2;
            SET @method_cashier := 7;
            SET @modality_monthly := 1;
            RETURN exists(select id
                from transactions
                where type_transaction_id in (@type_automatic, @type_manual)
                    and not ((method_transaction_id is null and modality_transaction_id = @modality_monthly) or (method_transaction_id = @method_cashier and modality_transaction_id = @modality_monthly))
                    and client_acount_id = id_account
                    and settlement_date >=datem
                    and settlement_date <= last_day(datem));
            END $$

DELIMITER ;



-- Archivo: new_get_months_owed_by_amg_rules.sql
DELIMITER $$

CREATE FUNCTION `new_get_months_owed_by_amg_rules`(settlement_date date, status_transaction_id int, type_payment int, method_payment int, _status_client_account int) RETURNS int
BEGIN
        set @validate_current_month = if(_status_client_account = 8 , true, false);
        set @validate_one_month = if(_status_client_account = 9 , true, false);

            set @validate_two_month = if(_status_client_account = 10 , true, false);

            set @approved_pay = (status_transaction_id in (1,5,8) or status_transaction_id is null);
               set @validate_lp_declined = DATE(settlement_date) BETWEEN date_add(now(), interval -4 month) and last_day(now());
            set @is_automatic_payment = method_payment = 0 and type_payment = 0;
            set @is_manual_payment = method_payment = 0 and type_payment = 1;
            set @is_other_payment = method_payment = 1 and (type_payment in (NULL, 2, 0, 1)); 
               
            set @tab = null;
        case

                    when  (@validate_lp_declined = true and @validate_current_month = true
                        and @is_automatic_payment 
                        and @approved_pay)  then   set @tab = 1;



                    when  (@validate_lp_declined = true and @validate_current_month = true
                        and @is_manual_payment
                        and @approved_pay)  then  set @tab = 2;



                    when  (@validate_lp_declined = true and @validate_current_month = true
                        and @is_other_payment
                        and @approved_pay)  then set @tab = 3;



                    when  (@validate_one_month = true
                        and ((@is_automatic_payment and @approved_pay) or @is_manual_payment or @is_other_payment))  then set @tab = 4;


                    when  (@validate_two_month = true
                        and ((@is_automatic_payment and @approved_pay) or @is_manual_payment or @is_other_payment))  then set @tab = 5;
                    else set @tab = 7;
                END CASE;

            RETURN @tab;
        END $$

DELIMITER ;



-- Archivo: new_global_income_monthly.sql
DELIMITER $$

CREATE FUNCTION `new_global_income_monthly`(datem date,id_program int,id_advisor int) RETURNS varchar(255) CHARSET latin1
BEGIN
                declare count_CE_program decimal(16,2) default 0;
                set @modality_monthly = 1;
                SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-01');
                SET @last_day_of_month = LAST_DAY(@first_day_of_month);
                set @isNotProgramId = (id_program is null) or (id_program = 0);
            
                select sum(amount) into count_CE_program
                from (  select distinct t.id,t.amount amount
                        from client_accounts ca
                        left join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                        inner join transactions t on t.client_acount_id = ca.id
                                and	t.modality_transaction_id = @modality_monthly
                                and status_transaction_id in (1,5,8)
                                and not t.type_transaction_id in (8,14,16,17)
                            where (aah.advisor_id = id_advisor or id_advisor = 0 or id_advisor is null) 
                                and (ca.program_id = id_program or @isNotProgramId)
                        and ca.migrating = 0 
                        and t.settlement_date >= @first_day_of_month
                        and t.settlement_date < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY)
                    group by t.id,2) a;
            
                RETURN format(ifnull(count_CE_program,0),2);
                END $$

DELIMITER ;



-- Archivo: new_total_amount_month.sql
DELIMITER $$

CREATE FUNCTION `new_total_amount_month`(datem date,id_program int,id_advisor int) RETURNS varchar(255) CHARSET latin1
BEGIN
            DECLARE count_CE_program DECIMAL(16,2) DEFAULT 0;
            DECLARE count_other_programs DECIMAL(16,2) DEFAULT 0;
            
            SET @modality_monthly = 1;
            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-01');
            SET @last_day_of_month = DATE_ADD(@first_day_of_month, INTERVAL 1 MONTH);
            SET @isNotProgramId = (id_program IS NULL) OR (id_program = 0);
        
            SET @new_range = program_date_for_new_range(id_program, @first_day_of_month);
            
            IF @new_range THEN
                SELECT SUM(IFNULL(amount, 0)) 
                INTO count_CE_program
                FROM (
                    SELECT DISTINCT t.id, IFNULL(t.amount, 0) amount
                    FROM client_accounts ca
                    INNER JOIN accounts_status_histories ash ON ash.client_acount_id = ca.id
                    LEFT JOIN accounts_advisors_histories aah ON aah.client_acount_id = ca.id
                    INNER JOIN transactions t ON t.client_acount_id = ca.id 
                        AND t.status_transaction_id IN (1, 5, 8) 
                        AND t.modality_transaction_id = 1
                        AND t.settlement_date >= @first_day_of_month 
                        AND t.settlement_date < @last_day_of_month
                        AND t.type_transaction_id NOT IN (3, 10, 11, 14, 15, 16, 17, 8)
                    WHERE DATE(ca.created_at) < @first_day_of_month  
                    AND (ca.program_id = id_program OR @isNotProgramId)
                    AND program_date_for_new_range(ca.program_id, @first_day_of_month)
                    AND ca.migrating = 0 
                    AND (
                        (ash.status IN (1, 8, 9, 10) AND DATE(ash.created_at) < @last_day_of_month) 
                        OR 
                        (ash.status IN (5, 11, 12, 13) AND ash.created_at >= @first_day_of_month AND ash.created_at < @last_day_of_month AND t.id IS NOT NULL)
                    )
                    AND (ash.updated_at IS NULL OR NOT ash.updated_at < @last_day_of_month)
                    GROUP BY t.id, amount
                ) a;
            END IF;	                                       

            IF NOT @new_range OR @isNotProgramId THEN 
                SELECT CAST(REPLACE(total_amount_month(@first_day_of_month, id_program, id_advisor), ',', '') AS DECIMAL(19,2)) 
                INTO count_other_programs;
            END IF;
            
            RETURN FORMAT(IFNULL(count_CE_program, 0) + IFNULL(count_other_programs, 0), 2);
        END $$

DELIMITER ;



-- Archivo: new_total_remaining_month.sql
DELIMITER $$

CREATE FUNCTION `new_total_remaining_month`(datem date,id_program int,id_advisor int) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
        declare count_CE_program decimal(16,2) default 0;
            declare count_other_programs decimal(16,2) default 0;
            
            set @type_automatic = 1;
            set @type_manual = 2;
            set @type_zero = 14;

            
            set @method_card = 1;
            set @method_cash = 2;
            set @method_cashier = 7;

            
            set @modality_monthly = 1;

            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-01');
            SET @last_day_of_month = LAST_DAY(@first_day_of_month); 
        
            set @isNotProgramId = (id_program is null) or (id_program = 0);
        
            SET @C_PARAGON_PROGRAM = 9;

            SET @new_range = program_date_for_new_range(id_program, @first_day_of_month);

            if(@new_range) then
                select sum(amount) into count_CE_program
                from (
                    select sum( get_last_recurring_billing_amount_in_range(ca.id, @first_day_of_month, @last_day_of_month ) ) amount
                from client_accounts ca
                    inner join accounts_status_histories ash on ash.client_acount_id = ca.id 
                    left join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                    inner join recurring_billings rb on rb.client_acount_id = ca.id and rb.updated_at is null
                    left join transactions t on t.client_acount_id = ca.id and t.status_transaction_id in (1,5,8)
                    AND t.modality_transaction_id = @modality_monthly
                    and not t.type_transaction_id  in (8,14,16,17)
                    and t.settlement_date >= @first_day_of_month and t.settlement_date < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY)
                where ca.created_at < @first_day_of_month
                and (( id_advisor is null or id_advisor = 0 or aah.advisor_id = id_advisor )
												and if( ca.program_id = 3 , true ,
													 aah.created_at < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY) and (aah.updated_at is null or not aah.updated_at < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY) ) )
											)   
                and (ca.program_id = id_program or @isNotProgramId)
                AND ca.program_id NOT IN ( @C_PARAGON_PROGRAM )
                AND program_date_for_new_range(ca.program_id, @first_day_of_month)
                and ca.migrating = 0 and (ca.created_at < @first_day_of_month or new_account_paid(ca.id, @first_day_of_month))
                and t.id is null
                and (  
                        ( (ash.status in (1,8,9,10) and  ash.created_at < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY) ) or
                        (ash.status in (11,12,13) and  ash.created_at >= @first_day_of_month and ash.created_at < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY) and t.id is not null) )
                    and (ash.updated_at is null or not ash.updated_at < DATE_ADD(@last_day_of_month, INTERVAL 1 DAY) ))
                ) a; 
            end if;	                                       

        if(! @new_range or @isNotProgramId )then 
            select cast(replace(total_remaining_month( @first_day_of_month,id_program,id_advisor),',','') as decimal(19,2)) into count_other_programs ;
        end if;
        RETURN format(ifnull(count_CE_program,0) + ifnull(count_other_programs,0),2);
        END $$

DELIMITER ;



-- Archivo: notes_lead.sql
DELIMITER $$

CREATE FUNCTION `notes_lead`(`id_lead` INT, `l` INT) RETURNS json
BEGIN

            RETURN (select JSON_ARRAYAGG(note) from(
                        select JSON_OBJECT('text',n.text,'created_at',n.created_at,'user_name',concat(us.first_name,' ',us.last_name),'image',us.image) note
                        from notes n 
                            inner join users us on us.id=n.user_id
                        where n.lead_id=id_lead
                        order by n.created_at desc
                        limit l) notes);
            END $$

DELIMITER ;



-- Archivo: offer_payment_order_code_generator.sql
DELIMITER $$

CREATE FUNCTION `offer_payment_order_code_generator`(
            _payment_format ENUM('BY PHONE','MAIL','ONLINE'),
            _payment_type ENUM('E-CHECK (CHECKING ACCOUNT)','CHECK (OVERNIGHT)','CASHIER CHECK','MONEY ORDER','DEBIT/CREDIT CARD')
        ) RETURNS varchar(15) CHARSET utf8mb3
BEGIN
            DECLARE _paycheck_type_symbol VARCHAR(2) DEFAULT '';
            DECLARE _payment_format_symbol VARCHAR(1)  DEFAULT '';
            DECLARE _payment_type_symbol VARCHAR(2) DEFAULT '';
            DECLARE _paycheck_number INT DEFAULT 0;
            DECLARE _current_date DATETIME;
            DECLARE _year_last_two_digits INT(2) DEFAULT 0;
            SET _current_date = NOW();
            SET _year_last_two_digits = DATE_FORMAT(_current_date, "%y");
            

            CASE
                WHEN _payment_type = 'E-CHECK (CHECKING ACCOUNT)' THEN
                    SET _payment_type_symbol = 'CA';
                WHEN _payment_type = 'CHECK (OVERNIGHT)' THEN
                    SET _payment_type_symbol = 'CH';
                WHEN _payment_type = 'CASHIER CHECK' THEN
                    SET _payment_type_symbol = 'CC';
                WHEN _payment_type = 'MONEY ORDER' THEN
                    SET _payment_type_symbol = 'CH';
                WHEN _payment_type = 'DEBIT/CREDIT CARD' THEN
                    SET _payment_type_symbol = 'DE';
            END CASE;

            SELECT IFNULL(COUNT(*) + 1, 1) INTO _paycheck_number
                FROM ds_offer_payment_orders dopo
                LEFT JOIN offer o ON o.id = dopo.offer_id
                WHERE dopo.payment_order_status_id <> 2
                AND YEAR(dopo.created_at) = YEAR(_current_date)
                AND o.payment_type = _payment_type
                AND o.payment_format = _payment_format;

            RETURN CONCAT(_paycheck_type_symbol, _payment_format_symbol, _payment_type_symbol, _year_last_two_digits, LPAD(_paycheck_number, 5, 0));
        END $$

DELIMITER ;



-- Archivo: old_or_new_compare_range.sql
DELIMITER $$

CREATE FUNCTION `old_or_new_compare_range`(
            settlement DATE, 
            id_program INT, 
            yearp INT, 
            nmonth INT, 
            _type INT
        ) RETURNS int
BEGIN  
            IF(!program_date_for_new_range(id_program,settlement)) THEN
                SET @start_date = DATE(concat(yearp,'-',nmonth,'-06'));
                SET @end_date = date_add(date_add(@start_date, interval 1 MONTH),interval -1 DAY);

                IF(_type = 1) THEN
                    RETURN (DATE(settlement) BETWEEN @start_date AND @end_date ); 
                ELSE	 
                    RETURN DATE(settlement) >= @start_date; 
                END IF;
            
            ELSE
                SET @start_date = DATE(concat(yearp,'-',nmonth,'-01'));
                SET @start_date_old = DATE(concat(yearp,'-',nmonth,'-06'));
                SET @end_date = last_day(@start_date);

                IF(_type = 1) THEN 
                    RETURN DATE(settlement) BETWEEN @start_date AND @end_date ;
                ELSE
                    RETURN DATE(settlement) >= @start_date AND IF(nmonth < month(settlement), date_add(DATE(settlement),interval -1 MONTH) >= @start_date_old  ,true );
                END IF; 
            END IF;
        END $$

DELIMITER ;



-- Archivo: paid_state.sql
DELIMITER $$

CREATE FUNCTION `paid_state`(id_user int , date_month varchar(2) , date_year int) RETURNS int
BEGIN
        declare p_state int;

            


		select cp.paid_state + 0 into p_state
		from commissions_payments cp
		where date_format(cp.commissions_date ,'%Y-%m') = concat(date_year,'-',date_month)
		and cp.user_id = id_user limit 1;

        RETURN p_state;
        END $$

DELIMITER ;



-- Archivo: paid_state_mc.sql
DELIMITER $$

CREATE FUNCTION `paid_state_mc`(id_user int , date_month int , date_year int, id_module int) RETURNS int
BEGIN
declare state int;
	
    select paid_state into state
	from modules_commission
	where (date(created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
        and module_id = id_module
		and user_id = id_user
        order by id desc
		limit 1;
    
RETURN state;
END $$

DELIMITER ;



-- Archivo: paid_state_p.sql
DELIMITER $$

CREATE FUNCTION `paid_state_p`(id_user int , date_month int , date_year int, id_module int) RETURNS int
BEGIN
declare state int;
	
    select sc.paid_state into state
	from sales_commissions sc
		inner join sales s on s.id = sc.sale_id
	where (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
		and s.type in (1,2)
        and s.module_id = id_module
		and sc.user_id = id_user
		and sc.state = 1
        order by sc.id desc
		limit 1;
    
RETURN state;
END $$

DELIMITER ;



-- Archivo: pay_end_date.sql
DELIMITER $$

CREATE FUNCTION `pay_end_date`(_date DATE) RETURNS date
begin
            return (SELECT DATE_ADD(DATE(concat(if(month(_date) = 01 and day(_date) in (1,2,3,4,5), year(_date) - 1, year(_date)),'-', 
        if(day(_date) in (1,2,3,4,5), if(month(_date) - 1 = 0, '12', month(_date) - 1), month(_date)),'-','05')), INTERVAL 1 month));
        END $$

DELIMITER ;



-- Archivo: pay_start_date.sql
DELIMITER $$

CREATE FUNCTION `pay_start_date`(_date DATE) RETURNS date
begin
            return (select  DATE(concat(if(month(_date) = 01 and day(_date) in (1,2,3,4,5), year(_date) - 1, year(_date)),'-', 
            if(day(_date) in (1,2,3,4,5), if(month(_date) - 1 = 0, '12', month(_date) - 1), month(_date)),'-','06')));
        END $$

DELIMITER ;



-- Archivo: payment_account_active.sql
DELIMITER $$

CREATE FUNCTION `payment_account_active`(
            datem DATE,
            id_program INT,
            id_advisor INT,
            type_payment INT,
            type_method INT,
            type_modality INT,
            taccount INT
        ) RETURNS int
BEGIN
            SET @type_automatic = 1;
            SET @type_manual = 2;
            SET @type_zero = 14;
            SET @type_others = 6;

            
            SET @method_card = 1;
            SET @method_cash = 2;
            SET @method_check = 3;
            SET @method_money_order = 4;
            SET @method_deposit = 5;

            
            SET @modality_monthly = 1;

            SET @C_PARAGON_PROGRAM = 9;

            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-06');
            SET @last_day_of_month = DATE_ADD(@first_day_of_month, INTERVAL 1 MONTH);

            RETURN (
                SELECT COUNT(DISTINCT IF(taccount = 1, ca.id, t.id))
                FROM client_accounts ca
                INNER JOIN accounts_status_histories ash ON ash.client_acount_id = ca.id
                INNER JOIN accounts_advisors_histories aah ON aah.client_acount_id = ca.id
                INNER JOIN transactions t ON t.client_acount_id = ca.id
                    AND t.status_transaction_id IN (1, 5, 8)
                    AND NOT t.type_transaction_id IN (8, 14, 16, 17)
                WHERE ca.created_at <= DATE_ADD(@first_day_of_month, INTERVAL -5 DAY)
                    AND (
                        (aah.advisor_id = id_advisor OR id_advisor = 0 OR id_advisor IS NULL)
                        AND aah.created_at < @last_day_of_month
                        AND (aah.updated_at IS NULL OR NOT aah.updated_at < @last_day_of_month)
                    )
                    AND (ca.program_id = id_program OR id_program = 0 OR id_program IS NULL)
                    AND ca.program_id NOT IN (@C_PARAGON_PROGRAM)
                    AND ca.migrating = 0
                    AND (
                        ca.created_at < @first_day_of_month
                        OR (t.settlement_date >= @first_day_of_month AND t.settlement_date < @last_day_of_month)
                    )
                    AND t.id IS NOT NULL
                    AND t.modality_transaction_id = 1
                    AND (
                        type_payment IS NULL
                        OR (
                            t.type_transaction_id = type_payment
                            AND IFNULL(t.method_transaction_id, 'null') = IFNULL(type_method, 'null')
                            AND t.modality_transaction_id = type_modality
                        )
                        OR (
                            type_payment = 0
                            AND (t.type_transaction_id, t.method_transaction_id, t.modality_transaction_id) IN (
                                (@type_manual, @method_cash, @modality_monthly),
                                (@type_manual, @method_check, @modality_monthly),
                                (@type_manual, @method_money_order, @modality_monthly),
                                (@type_manual, @method_deposit, @modality_monthly)
                            )
                        )
                    )
                    AND t.settlement_date >= @first_day_of_month
                    AND t.settlement_date < @last_day_of_month
                    AND NOT program_date_for_new_range(ca.program_id,t.settlement_date)
                    AND (
                        (
                            (ash.status IN (1, 8, 9, 10) AND ash.created_at < @last_day_of_month)
                            OR (ash.status IN (3, 5) 
                                AND ash.created_at >= @first_day_of_month 
                                AND ash.created_at < @last_day_of_month 
                                AND t.id IS NOT NULL)
                        )
                        AND (ash.updated_at IS NULL OR NOT ash.updated_at < @last_day_of_month)
                    )
            );
        END $$

DELIMITER ;



-- Archivo: payment_new_account_active.sql
DELIMITER $$

CREATE FUNCTION `payment_new_account_active`(datem date,id_program int,id_advisor int,type_payment int, type_method int, type_modality int, taccount int) RETURNS int
BEGIN
            SET @type_automatic = 1;
            SET @type_manual  = 2;
            SET @type_zero = 14;
            
            SET @method_card = 1;
            SET @method_cash = 2;
            SET @method_check = 3;
            SET @method_money_order = 4;
            SET @method_deposit = 5;
            SET @type_others = 6;
            
            SET @modality_monthly = 1;
            
            SET @count_CE_program = 0; 
            SET @count_other_programs = 0;
            
            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-01');
            SET @last_day_of_month = DATE_ADD(@first_day_of_month, INTERVAL 1 MONTH); 
            SET @isNotProgramId = (id_program IS NULL) OR (id_program = 0);
            
            IF program_date_for_new_range(id_program, @first_day_of_month) THEN
                SELECT COUNT(DISTINCT IF(taccount = 1, ca.id, t.id)) 
                INTO @count_CE_program
                FROM client_accounts ca
                INNER JOIN accounts_status_histories ash ON ash.client_acount_id = ca.id
                LEFT JOIN accounts_advisors_histories aah ON aah.client_acount_id = ca.id
                INNER JOIN transactions t ON t.client_acount_id = ca.id 
                    AND t.status_transaction_id IN (1, 5, 8) 
                    AND t.modality_transaction_id = 1
                    AND t.settlement_date >= @first_day_of_month 
                    AND t.settlement_date < @last_day_of_month
                    AND t.type_transaction_id NOT IN (3, 10, 11, 14, 15, 16, 17, 8)
                WHERE DATE(ca.created_at) < @first_day_of_month 
                AND (ca.program_id = id_program OR @isNotProgramId)
                AND program_date_for_new_range(ca.program_id, @first_day_of_month)
                AND ca.migrating = 0 
                AND ((ash.status IN (1, 8, 9, 10) AND DATE(ash.created_at) < @last_day_of_month) 
                        OR
                        (ash.status IN (5, 11, 12, 13) AND ash.created_at >= @first_day_of_month AND ash.created_at < @last_day_of_month AND t.id IS NOT NULL)
                    )
                AND (ash.updated_at IS NULL OR NOT ash.updated_at < @last_day_of_month)
                AND (type_payment IS NULL OR t.type_transaction_id = type_payment)
                AND (type_method IS NULL OR t.method_transaction_id = type_method)
                AND (type_modality IS NULL OR t.modality_transaction_id = type_modality);
            END IF;
            
            IF !program_date_for_new_range(id_program, @first_day_of_month) OR @isNotProgramId THEN 
                SELECT payment_account_active(datem, id_program, id_advisor, type_payment, type_method, type_modality, taccount) 
                INTO @count_other_programs;
            END IF;
            
            RETURN @count_CE_program + @count_other_programs;
        END $$

DELIMITER ;



-- Archivo: percentage_department.sql
DELIMITER $$

CREATE FUNCTION `percentage_department`(date_month varchar(4) , date_year varchar(4)) RETURNS decimal(16,2)
BEGIN

 	set @percent = (select pm.percentage_department
		from percentage_monthly_commissions pm
		where
			date_format(pm.date_percentage,'%Y-%m') = concat(date_year,'-',date_month));



RETURN @percent;

        END $$

DELIMITER ;



-- Archivo: program_date_for_new_range.sql
DELIMITER $$

CREATE FUNCTION `program_date_for_new_range`(
            _program_id INT,
            _datem DATE
        ) RETURNS tinyint(1)
BEGIN
            
            RETURN EXISTS (
                SELECT id
                FROM program_deployment_dates pdd
                WHERE 
                    program_id = _program_id
                    AND _datem >= deployment_date
                    AND pdd.new_range = 1
            );
        END $$

DELIMITER ;



-- Archivo: programs_with_new_schedule.sql
DELIMITER $$

CREATE FUNCTION `programs_with_new_schedule`(
            _start_date DATE
        ) RETURNS varchar(255) CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci
BEGIN
            DECLARE id_list VARCHAR(255);

            SELECT GROUP_CONCAT(pdd.program_id) INTO id_list
            FROM program_deployment_dates pdd
            WHERE pdd.deployment_date <= _start_date AND pdd.schedule = 1;

            RETURN IFNULL(id_list, '0');
        END $$

DELIMITER ;



-- Archivo: programs_with_new_status.sql
DELIMITER $$

CREATE FUNCTION `programs_with_new_status`(
            _start_date DATE
        ) RETURNS varchar(255) CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci
BEGIN
            DECLARE id_list VARCHAR(255);

            SELECT GROUP_CONCAT(pdd.program_id) INTO id_list
            FROM program_deployment_dates pdd
            WHERE pdd.deployment_date <= _start_date AND pdd.status = 1;

            RETURN IFNULL(id_list, '0');
        END $$

DELIMITER ;



-- Archivo: rate_selected.sql
DELIMITER $$

CREATE FUNCTION `rate_selected`(pid int) RETURNS longtext CHARSET utf8mb4 COLLATE utf8mb4_bin
BEGIN
                 declare j json;
                 SELECT CONCAT('[', better_result, ']') AS rate FROM
                    (
                        SELECT GROUP_CONCAT('{', my_json, '}' SEPARATOR ',') AS better_result FROM
                        (
                          SELECT 
                            CONCAT
                            (
                              '"rate_id":'   ,  rate_id ,',' ,'"quantity":',quantity
                            ) AS my_json
                          FROM rate_sales where sale_id=pid
                        ) AS more_json
                    ) AS yet_more_json into j;
            RETURN j;
            END $$

DELIMITER ;



-- Archivo: remove_alpha.sql
DELIMITER $$

CREATE FUNCTION `remove_alpha`(inputPhoneNumber VARCHAR(50)) RETURNS varchar(50) CHARSET latin1
BEGIN
                declare inputLenght INT default 0;
                
                    declare counter INT default 1;
                
                    declare sanitizedText VARCHAR(50) default '';
                
                    declare oneChar VARCHAR(1) default '';
                
                    if not ISNULL(inputPhoneNumber)
                    then
                    set
                inputLenght = length(inputPhoneNumber);

                while counter <= inputLenght DO
                        set
                oneChar = SUBSTRING(inputPhoneNumber, counter, 1);

                if (oneChar regexp ('^[0-9]+$'))
                        then
                        set
                sanitizedText = Concat(sanitizedText, oneChar);
                end if;

                set
                counter = counter + 1;
                end while;
                end if;

                return sanitizedText;
            END $$

DELIMITER ;



-- Archivo: round_robin_round_letter.sql
DELIMITER $$

CREATE FUNCTION `round_robin_round_letter`() RETURNS int
BEGIN
	declare total int;
    declare total_users int;
    
    select (count(*) - 1) into total_users
	from user_module um
		join users u on u.id = um.user_id and u.status = 1
	where module_id = 9
	and role_id = 3;

	SET @i = 0; 
    
	select um.user_id into total
	from user_module um
		join users u on u.id = um.user_id and u.status = 1
	where module_id = 9    
	and um.role_id = 3
    and um.user_id not in (select nrl.advisor_id from ncr_round_letters nrl
						join (select distinct(ncr_round_letters_id) id
					from (select ncr_round_letters_id, (@i := @i + 1) count from ncr_round_letters_tracking where state = 5 order by created_at desc) as round
					limit total_users) as round on round.id = nrl.id) 
	order by um.user_id limit 1;
	
RETURN total;
END $$

DELIMITER ;



-- Archivo: route_module.sql
DELIMITER $$

CREATE FUNCTION `route_module`(id_user int) RETURNS varchar(255) CHARSET latin1
BEGIN
        RETURN (select m.route 
                from modules m
                    inner join user_module um on um.module_id = m.id
                where m.id <> 1 and um.user_id = id_user order by m.id limit 1);
        END $$

DELIMITER ;



-- Archivo: split_string.sql
DELIMITER $$

CREATE FUNCTION `split_string`(str VARCHAR(255), delim VARCHAR(5), pos INT) RETURNS varchar(255) CHARSET utf8mb3
RETURN REPLACE(SUBSTRING(SUBSTRING_INDEX(str, delim, pos),
               CHAR_LENGTH(SUBSTRING_INDEX(str, delim, pos-1)) + 1),
               delim, '') $$

DELIMITER ;



-- Archivo: split_string_for_searching.sql
DELIMITER $$

CREATE FUNCTION `split_string_for_searching`(cadena VARCHAR(255)) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
            IF cadena = '' THEN
                RETURN '';
            ELSE
                SET @resultado = CONCAT('%', REPLACE(cadena, ' ', '%'), '%');
                RETURN @resultado;
            END IF;
            END $$

DELIMITER ;



-- Archivo: status_hold_account.sql
DELIMITER $$

CREATE FUNCTION `status_hold_account`(id_account varchar(36)) RETURNS int
BEGIN
                declare status_id int;
                select
                    case 
                        when (DATE_ADD(now(), INTERVAL -90 DAY) >= end_transaction(ca1.id)  and  DATE_ADD(now(), INTERVAL -180 DAY) < end_transaction(ca1.id)  ) or  (end_transaction(ca1.id)   is null  and DATE_ADD(now(), INTERVAL -90 DAY) >= ca1.created_at and DATE_ADD(now(), INTERVAL -180 DAY) < ca1.created_at) then 1
                        when DATE_ADD(now(), INTERVAL -180 DAY) >= end_transaction(ca1.id)   or (end_transaction(ca1.id)   is null  and DATE_ADD(now(), INTERVAL -180 DAY) >= ca1.created_at) then 2
                        else 1
                    end `status` into status_id
                from client_accounts ca1  
                where ca1.status in (1,2) and DATE_ADD(now(), INTERVAL -90 DAY) >= ca1.created_at and ca1.id = id_account;
            RETURN status_id;
            END $$

DELIMITER ;



-- Archivo: sum_charge_users.sql
DELIMITER $$

CREATE FUNCTION `sum_charge_users`(id_program int, id_charge int, date_year int, date_month int, id_type int, total_month decimal(16,2)) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    declare _date date;
	set _date = date(concat(date_year,'-',date_month,'-01'));
        set @type_charge := 7;
        set @type_others := 6;
		
        SELECT sum(t.amount) into total 
		FROM additional_charges ac
			join transactions t on t.id = ac.transactions_id and t.type_transaction_id in (@type_charge, @type_others) 
            and t.status_transaction_id in (1,5)
            join client_accounts ca on ca.id = ac.client_acount_id and ca.program_id = id_program
        where ac.state_charge = 1
        and ac.type_charge = id_charge
        and t.settlement_date BETWEEN _date and date_add(last_day(_date), interval 1 day);
		

    if(id_type = 0)then 

        set total = (total / total_month) * 100;

    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: sum_charges_commissions.sql
DELIMITER $$

CREATE FUNCTION `sum_charges_commissions`(user_id_p int, month_p int, year_p int, module_id_p int) RETURNS decimal(16,2)
begin
       declare total decimal(16,2) default 0;
            
            declare is_supervisor int default 0;
            
            select if(um.role_id = 2, 1, 0) into is_supervisor from user_module um where um.user_id = user_id_p and um.module_id = module_id_p;
            
            select 
            sum(case
	            	when date(t.created_at) > '2022-01-06' then  
			            case 
				                when is_supervisor = 1 and user_id_p != ce.created_by then
				                    ((t.amount  - cfl.loss) * cc.percentage / 100) * 0.20
				                when is_supervisor = 1 and user_id_p = ce.created_by then 
				                    (t.amount  - cfl.loss) * cc.percentage / 100
				                when is_supervisor = 0 then 
				                    ((t.amount  - cfl.loss) * cc.percentage / 100) - (((t.amount  - cfl.loss)* cc.percentage / 100) * 0.20)
				            end
		           else
			            case 
			                when is_supervisor = 1 and user_id_p != ce.created_by then
			                    (cfl.profit * cc.percentage / 100) * 0.20
			                when is_supervisor = 1 and user_id_p = ce.created_by then 
			                    cfl.profit * cc.percentage / 100
			                when is_supervisor = 0 then 
			                    (cfl.profit * cc.percentage / 100) - ((cfl.profit * cc.percentage / 100) * 0.20)
			            end
            end)
            
            into total from charges_entrances ce 
            join transactions t on ce.transaction_id = t.id
            join user_module um on ce.created_by = um.user_id 
            join types_charges tc on ce.charge_id = tc.id 
            join charges_fee_loss cfl on ce.charge_fee_loss_id = cfl.id 
            join charges_commissions cc on ce.id_commissions_type = cc.id
            where date_format(ce.created_at, "%m") * 1 = month_p
            and date_format(ce.created_at, "%Y") * 1 = year_p
            and um.module_id = module_id_p
            and um.main_module = 1
            and (is_supervisor = 1 or ce.created_by = user_id_p)
            and ce.client_account_id is not null
            and t.status_transaction_id in (1, 5) 
            group by date_format(ce.created_at , "%m");
        
            return(
                    total
                );
        END $$

DELIMITER ;



-- Archivo: sum_commision_ce_digital.sql
DELIMITER $$

CREATE FUNCTION `sum_commision_ce_digital`(user_id_p int, month_p int, year_p int, module_id_p int) RETURNS decimal(16,2)
begin
        declare total decimal(16,2) default 0;
                    DECLARE role_id INT default 0;
                    declare sum_ce_digital decimal(16,2) default 0;
                    
                    SELECT um.role_id into role_id FROM user_module um WHERE um.module_id = module_id_p AND um.user_id = user_id_p;
                   
                    SELECT IFNULL(SUM(IFNULL(ac.amount,0)),0) INTO sum_ce_digital
                    FROM agent_commision ac
                    WHERE ac.agent_id  = user_id_p
                    AND DATE_FORMAT(ac.created_at, "%m") * 1 = month_p
                    AND DATE_FORMAT(ac.created_at, "%Y") * 1 = year_p;
                
                    SET total = total + sum_ce_digital;
                
                    SELECT IFNULL(SUM(IFNULL(sacc.amount,0)),0) INTO sum_ce_digital
                    FROM sup_assist_commissions_ced sacc
                    WHERE sacc.user_id = user_id_p
                    AND DATE_FORMAT(sacc.created_at, "%m") * 1 = month_p
                    AND DATE_FORMAT(sacc.created_at, "%Y") * 1 = year_p;
                
                    SET total = total + sum_ce_digital;
                   
                    SELECT IFNULL(SUM(IFNULL(sc.commission,0) - IFNULL(sc.amount_for_sup,0) - IFNULL(sc.amount_for_ceo,0) - IFNULL(sc.amount_for_assist_sup,0)),0) INTO sum_ce_digital
                    FROM sales_commissions sc
                    JOIN sales s ON sc.sale_id = s.id AND s.module_id IN (20,26)
                    WHERE sc.user_id = user_id_p
                    AND sc.state = 1
                    AND DATE_FORMAT(sc.created_at, "%m") * 1 = month_p
                    AND DATE_FORMAT(sc.created_at, "%Y") * 1 = year_p;
                
                    SET total = total + sum_ce_digital;
                
                    SELECT IFNULL(SUM(IFNULL(gcs.amount,0)),0) INTO sum_ce_digital
                    FROM general_commissions_supervisors gcs
                    WHERE gcs.user_id = user_id_p
                    AND DATE_FORMAT(gcs.created_at, "%m") * 1 = month_p
                    AND DATE_FORMAT(gcs.created_at, "%Y") * 1 = year_p
                    AND gcs.module_id IN (20,26)
                    AND gcs.status_commission = 1;
                
                    SET total = total + sum_ce_digital;
                
                    return( total );
                END $$

DELIMITER ;



-- Archivo: sum_commission.sql
DELIMITER $$

CREATE FUNCTION `sum_commission`(id_user int , date_month int , date_year int, type_t int) RETURNS decimal(16,2)
BEGIN
						declare amount_user decimal(16,2);
						declare id_role int;
						declare total decimal(16,2);
						declare amount_department decimal(16,2);
						declare amount_ceo decimal(16,2);
						declare amount_super decimal(16,2);
						declare amount_s_a decimal(16,2);
						declare amount_programs decimal(16,2);
						declare amount_programs_sup_crm decimal(16,2);
							
							set @date_gen = date(concat(date_year,'-',date_month,'-01'));
							
							if(@date_gen < '2022-04-01') then
								set @commission_super = 0.2;
                                if(id_user = 7) then
									set @is_angela_sup = true;
								else
									set @is_angela_sup = false;
								end if;
							else
								set @commission_super = 0.1;
							end if;
										
			
							select ifnull(sum(sc.commission),0) into amount_department
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
							and sc.state = 1
							and um.module_id = 2
							and um.main_module = 1
							and um.role_id in (3,5,13)
							and u.status = 1
							and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
							and (date(s.created_at) >= '2020-01-01');
			
							select ifnull(sum(sc.commission),0) into amount_programs_sup_crm
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id and um.main_module is null
								inner join sales s on s.id = sc.sale_id
							where s.type in (0)
								and sc.state = 1
								and um.module_id = 2
								and um.role_id in (3,5,13)
								and u.status = 1
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)));
			
						
						
						
						
						
						
						
						
						
						
						

                        CREATE TEMPORARY TABLE IF NOT EXISTS temp_amount_programs 
	                    ENGINE=MEMORY
	                    AS (
		                    select ifnull(sum(sc.commission),0) amount
							from sales_commissions sc
							inner join users u on u.id = sc.user_id
							inner join user_module um on um.user_id = u.id
							inner join sales s FORCE INDEX (PRIMARY) on s.id = sc.sale_id
							where s.type in (1,2)
							and sc.state = 1
							and um.module_id <> 2
							and um.role_id in (3,5,13)
							and u.status = 1
							and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
	                    );
	                                              
	                    SELECT tap.amount INTO amount_programs FROM temp_amount_programs tap;
			
						if(type_t = 0) then
							select ifnull(sum(sc.commission),0) , um.role_id into amount_user, id_role
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
								and sc.state = 1
								and (um.module_id = 2)
								and (u.id = id_user)
								and (u.status = 1)
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01')
							group by um.role_id;
			
						
							set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);
							select ifnull(sum(sc.commission),0) into @comission_crm
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id and um.module_id = @otherModule
								inner join sales s on s.id = sc.sale_id
							where s.type in (0)
								and sc.state = 1
								and um.role_id in (3,5,13)
								and u.status = 1
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
			
							set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));
							if(id_role = 1)then
								set total = amount_user;
							elseif((id_role=2 and @date_gen > '2022-03-31') or @is_angela_sup)then
								set total = amount_user  + (amount_programs_sup_crm * 0.10) + (amount_department * @commission_super) ;
								if(@is_angela_sup) then
									set total = total +(amount_department * 0.10);
								end if;
							elseif(@isSupervisorInOtherModule = 1) then
								set total = (@comission_crm * 0.10) + amount_user - (amount_user * 0.10);
							else
								set total = amount_user - (amount_user * 0.20);
							end if;
			
						elseif(type_t = 7) then
							select ifnull(sum(sc.commission * sc.percentage_pay / 100 ),0) , um.role_id into amount_user, id_role
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
								and sc.state = 1
								and (um.module_id = 2)
								and (u.id = id_user)
								and (u.status = 1)
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01')
							group by um.role_id;

							
							set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);
							select ifnull(sum(sc.commission),0) into @comission_crm
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id and um.module_id = @otherModule
								inner join sales s on s.id = sc.sale_id
							where s.type in (0)
								and sc.state = 1
								and um.role_id in (3,5,13)
								and u.status = 1
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
			
							set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));
							if(id_role = 1)then
								set total = amount_user;
							elseif((id_role=2 and @date_gen > '2022-03-31') or @is_angela_sup)then
								set total = amount_user  + (amount_programs_sup_crm * 0.10) + (amount_department * @commission_super) ;
								if(@is_angela_sup) then
									set total = total +(amount_department * 0.10);
								end if;
							elseif(@isSupervisorInOtherModule = 1) then
								set total = (@comission_crm * 0.10) + amount_user - (amount_user * 0.10);
							else
								set total = amount_user - (amount_user * 0.20);
							end if;
			
						elseif(type_t = 1) then
			
							select ifnull(sum(sc.commission),0) into amount_ceo
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
								and sc.state = 1
								and (um.module_id = 2)
								and (um.role_id = 1)
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
			
							select ifnull(sum(sc.commission),0) into amount_super
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
								and sc.state = 1
								and (um.module_id = 2)
								and (um.role_id = 2)
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
							set amount_super = amount_user  + (amount_programs_sup_crm * 0.10) + (amount_department * @commission_super) ;
								if(@is_angela_sup) then
									set amount_super = amount_super +(amount_department * 0.10);
								end if;
							set amount_s_a = amount_department - (amount_department * 0.20);
							set total = amount_ceo + amount_s_a + amount_super;
			
						elseif(type_t = 2)then
			
							select ifnull(sum(sc.commission),0) into amount_user
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
								and sc.state = 1
								and (um.module_id = 2)
								and (u.id = id_user)
								and (u.status = 1)
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
			
							
			
							set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));
							if(@isSupervisorInOtherModule = 1) then
								set total = amount_user;
							else
								set total = amount_user;
							end if;
			
						elseif(type_t = 8) then
			
							set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);
							select ifnull(sum(sc.commission),0) into @comission_crm
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id and um.module_id = @otherModule
								inner join sales s on s.id = sc.sale_id
							where s.type in (0)
								and sc.state = 1
								and um.role_id in (3,5,13)
								and u.status = 1
								and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
								and (date(s.created_at) >= '2020-01-01');
			
							set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));
							if(@isSupervisorInOtherModule = 1) then
								set total = @comission_crm * 0.10;
							else
								set total = 0;
							end if;
			
						elseif(type_t = 3)then
							select ifnull(sum(sc.commission),0) into amount_department
							from sales_commissions sc
								inner join users u on u.id = sc.user_id
								inner join user_module um on um.user_id = u.id
								inner join sales s on s.id = sc.sale_id
							where s.type = 0
							and sc.state = 1
							and um.module_id = 2
							and um.main_module = 1
							and um.role_id in (3,5,13)
							and u.status = 1
							and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
							and (date(s.created_at) >= '2020-01-01');
			
							set total = amount_department * 0.20;
			
						elseif(type_t = 4)then
			
							set total = amount_programs_sup_crm * 0.10;
			
						end if;
						return(total);
					END $$

DELIMITER ;



-- Archivo: sum_commission_p.sql
DELIMITER $$

CREATE FUNCTION `sum_commission_p`(id_user int , date_month int , date_year int, type_t int, modul int) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    declare amount_user decimal(16,2);
    declare id_role int;
    declare amount_department decimal(16,2);
    declare amount_ceo decimal(16,2);
	declare amount_super decimal(16,2);
            
    select ifnull(sum(sc.commission),0) into amount_department
	from sales_commissions sc
		inner join users u on u.id = sc.user_id
		inner join user_module um on um.user_id = u.id and um.module_id = modul
		inner join sales s on s.id = sc.sale_id
	where s.type in (1,2)
		and sc.state = 1
		and s.module_id = modul
		and um.role_id in (3,5)
		and u.status = 1
		and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
        and (date(sc.approve_date) >= '2020-09-01');
    
    if(type_t = 0) then 
		
        select ifnull(sum(sc.commission),0), um.role_id into amount_user, id_role
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
            inner join sales s on s.id = sc.sale_id
		where sc.state = 1
			and s.type in (1,2)
            and s.module_id = modul            
			and u.id = id_user
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01')
			group by um.role_id;
			
		if(id_role = 1)then
			set total = amount_user;
		elseif(id_role = 2)then
			
			if(curdate() >= '2020-09-01') then 
				set total = amount_user + (amount_department * 0.20);
			else
				set total = amount_user + (amount_department * 0.10);
			end if;
		else
			set total = amount_user - (amount_user * 0.20);
        end if;
	
    elseif(type_t = 1)then 
		
        select ifnull(sum(sc.commission),0) into amount_ceo
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
			inner join sales s on s.id = sc.sale_id
		where s.type in (1,2)
			and sc.state = 1
			and s.module_id = modul
			and um.role_id = 1
			and u.status = 1
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
            
		select ifnull(sum(sc.commission),0) into amount_super
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id
			inner join sales s on s.id = sc.sale_id
		where s.type in (1,2)
			and sc.state = 1
			and s.module_id = modul
			and um.role_id = 2
			and u.status = 1
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
		
        set amount_super = amount_super + (amount_department * 0.10);
        set amount_department = amount_department - (amount_department * 0.20);
		set total = amount_ceo + amount_super + amount_department;
	
    elseif(type_t = 2)then 
		           
		select ifnull(sum(sc.commission),0) into total
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
            inner join sales s on s.id = sc.sale_id
		where sc.state = 1
			and s.type in (1,2)
			and u.id = id_user
            and s.module_id = modul
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
	
    elseif(type_t = 3)then 
    
		select ifnull(sum(sc.commission),0) into amount_department
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
			inner join sales s on s.id = sc.sale_id
		where s.type in (1,2)
			and sc.state = 1
			and s.module_id = modul
			and um.role_id in (3,5)
			and u.status = 1
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
            
		
		if(curdate() >= '2020-09-01') then 
			set total = amount_department * 0.20;
		else
			set total = amount_department * 0.10;
		end if;
    
    elseif(type_t = 4)then
    
		select ifnull(sum(sc.commission),0) into total
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
			inner join sales s on s.id = sc.sale_id
		where s.type in (1,2)
			and sc.state = 1
			and s.module_id in (3,5,6,7,8,10,11,14)
			and u.status = 1
			and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
		
        set total = total - (total * 0.10);
        
	elseif(type_t = 5)then	 
        
		select ifnull(sum(sc.commission),0), um.role_id into amount_user, id_role
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = modul
            inner join sales s on s.id = sc.sale_id
		where sc.state = 1
			and s.type in (1,2)
            and s.module_id = modul
			and u.id = id_user
			and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
			
		if(id_role = 1)then
			set total = amount_user;
		elseif(id_role = 2)then
        
			select ifnull(sum(sc.commission),0) into amount_department
			from sales_commissions sc
				inner join users u on u.id = sc.user_id
				inner join user_module um on um.user_id = u.id and um.module_id = modul
				inner join sales s on s.id = sc.sale_id
			where s.type in (1,2)
				and sc.state = 1
				and s.module_id = modul
				and um.role_id in (3,5)
				and u.status = 1
				and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))))
                and (date(sc.approve_date) >= '2020-09-01');
                
			set total = amount_user + (amount_department * 0.10);
		else
			set total = amount_user - (amount_user * 0.20);
        end if;
        
	elseif(type_t = 6)then 
    
		select ifnull(sum(sc.commission),0) into amount_department
		from sales_commissions sc
			inner join users u on u.id = sc.user_id
			inner join sales s on s.id = sc.sale_id
		where s.type in (1,2)
			and sc.state = 1
			and s.module_id = modul
			and u.status = 1
			and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))))
            and (date(sc.approve_date) >= '2020-09-01');
            
		set total =amount_department - (amount_department * 0.10);
        
    end if;
    
RETURN total;
END $$

DELIMITER ;



-- Archivo: sum_commission_p_v2.sql
DELIMITER $$

CREATE FUNCTION `sum_commission_p_v2`(id_user int , date_month int , date_year int, type_t int, modul int) RETURNS decimal(16,2)
BEGIN
                                                    declare total decimal(16,2);
                                                    declare amount_user decimal(16,2);
                                                    declare id_role int;
                                                    declare amount_department decimal(16,2) default 0;
                                                    declare amount_ceo decimal(16,2);
                                                    declare amount_super decimal(16,2);
                                                    declare re_module_id int;
                                                    declare rol_in_module int;
                                                   
                                                    set re_module_id = modul;
                                                    if (modul = 26) then
                                                        select role_id into rol_in_module from user_module um where um.user_id = id_user and um.module_id = modul;
                                                           if (rol_in_module is null) then
                                                              set re_module_id = 6;
                                                           end if;	  
                                                    end if;
                                                    
                                                            
                                                    select ifnull(sum(sc.commission),0) into amount_department
                                                    from sales_commissions sc
                                                        inner join users u on u.id = sc.user_id
                                                        inner join user_module um on um.user_id = u.id and um.module_id = modul
                                                        inner join sales s on s.id = sc.sale_id
                                                    where s.type in (1,2)
                                                        and sc.state = 1
                                                        and s.module_id = modul
                                                        and um.role_id in (3,5)
                                                        and u.status = 1
                                                        and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))));
                                                    
                                                    if(type_t = 0) then 
                                                         
                                                        
                                                        
                                                    
                                                        select um.role_id into id_role from user_module um where um.user_id = id_user and um.module_id = modul;
                                                        
                                                        select IFNULL(SUM(IFNULL(sc.commission,0) - IFNULL(sc.amount_for_sup,0) - IFNULL(sc.amount_for_ceo,0) - IFNULL(sc.amount_for_assist_sup,0)),0),
                                                        um.role_id into amount_user, id_role
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id and um.module_id = re_module_id
                                                            inner join sales s on s.id = sc.sale_id
                                                        where sc.state = 1
                                                            and s.type in (1,2)
                                                            and s.module_id = modul            
                                                            and u.id = id_user
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) 
                                                           and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
                                                        group by um.role_id;
                                                        
                                                        
                                                        if (id_role = 2 or id_role = 14) then
                                                            SELECT IFNULL(SUM(gcs.amount),0) into amount_department
                                                            FROM general_commissions_supervisors gcs 
                                                            JOIN sales_commissions sc ON gcs.sale_commission_id = sc.id 
                                                            JOIN sales s ON sc.sale_id = s.id 
                                                            where gcs.type_from = 2 and gcs.user_id = id_user
                                                            AND (date(gcs.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(gcs.created_at) 
                                                            <= last_day(date(concat(date_year,'-',date_month,'-01')))))
                                                            AND gcs.status_commission = 1
                                                            AND s.module_id = modul;
                                                        end if;
                                                            
                                                        if(id_role = 1) then
                                                            set total = amount_user; 
                                                            
                                                        elseif(id_role = 2 or id_role = 14) then
                                                            set total = amount_user + amount_department; 
                                                        else 
                                                            set total = amount_user; 
                                                        end if;
                                                       
                                                    
                                                    elseif(type_t = 1)then 
                                                        
                                                        select ifnull(sum(sc.commission),0) into amount_ceo
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id and um.module_id = modul
                                                            inner join sales s on s.id = sc.sale_id
                                                        where s.type in (1,2)
                                                            and sc.state = 1
                                                            and s.module_id = modul
                                                            and um.role_id = 1
                                                            and u.status = 1
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
                                                            and (date(sc.approve_date) >= '2020-09-01');
                                                            
                                                        select ifnull(sum(sc.commission),0) into amount_super
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id
                                                            inner join sales s on s.id = sc.sale_id
                                                        where s.type in (1,2)
                                                            and sc.state = 1
                                                            and s.module_id = modul
                                                            and um.role_id = 2
                                                            and u.status = 1
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
                                                            and (date(sc.approve_date) >= '2020-09-01');
                                                        
                                                        set amount_super = amount_super + (amount_department * 0.10);
                                                        set amount_department = amount_department - (amount_department * 0.20);
                                                        set total = amount_ceo + amount_super + amount_department;
                                                    
                                                    elseif(type_t = 2)then 
                                                                   
                                                        select ifnull(sum(sc.commission),0) into total
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id and um.module_id = re_module_id
                                                            inner join sales s on s.id = sc.sale_id
                                                        where sc.state = 1
                                                            and s.type in (1,2)
                                                            and u.id = id_user
                                                            and s.module_id = modul
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))));
                                                    
                                                    elseif(type_t = 3)then 
                                                           
                                                           
                                                        SELECT IFNULL(SUM(gcs.amount),0) into amount_department
                                                            FROM general_commissions_supervisors gcs where gcs.type_from = 2 and gcs.user_id = id_user
                                                            AND (date(gcs.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(gcs.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
                                                            AND gcs.status_commission = 1 and gcs.module_id = modul;
                                                        
                                                        set total = amount_department;
                                                            
                                                    
                                                    elseif(type_t = 4)then
                                                    
                                                        select ifnull(sum(sc.commission),0) into total
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id and um.module_id = modul
                                                            inner join sales s on s.id = sc.sale_id
                                                        where s.type in (1,2)
                                                            and sc.state = 1
                                                            and s.module_id in (3,5,6,7,8,10,11,14)
                                                            and u.status = 1
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-',date_month,'-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-',date_month,'-01')))));
                                                        
                                                        set total = total - (total * 0.10);
                                                        
                                                    elseif(type_t = 5)then	 
                                                        
                                                        select ifnull(sum(sc.commission),0), um.role_id into amount_user, id_role
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join user_module um on um.user_id = u.id and um.module_id = modul
                                                            inner join sales s on s.id = sc.sale_id
                                                        where sc.state = 1
                                                            and s.type in (1,2)
                                                            and s.module_id = modul
                                                            and u.id = id_user
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))))
                                                        group by um.role_id;
                                                            
                                                        if(id_role = 1)then
                                                            set total = amount_user;
                                                        elseif(id_role = 2)then
                                                        
                                                            select ifnull(sum(sc.commission),0) into amount_department
                                                            from sales_commissions sc
                                                                inner join users u on u.id = sc.user_id
                                                                inner join user_module um on um.user_id = u.id and um.module_id = modul
                                                                inner join sales s on s.id = sc.sale_id
                                                            where s.type in (1,2)
                                                                and sc.state = 1
                                                                and s.module_id = modul
                                                                and um.role_id in (3,5)
                                                                and u.status = 1
                                                                and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))));
                                                                
                                                            set total = amount_user + (amount_department * 0.10);
                                                        else
                                                            set total = amount_user - (amount_user * 0.20);
                                                        end if;
                                                        
                                                    elseif(type_t = 6)then 
                                                    
                                                        select ifnull(sum(sc.commission),0) into amount_department
                                                        from sales_commissions sc
                                                            inner join users u on u.id = sc.user_id
                                                            inner join sales s on s.id = sc.sale_id
                                                        where s.type in (1,2)
                                                            and sc.state = 1
                                                            and s.module_id = modul
                                                            and u.status = 1
                                                            and (date(sc.approve_date) >= date(concat(date_year,'-01-01')) and (date(sc.approve_date) <= last_day(date(concat(date_year,'-12-01')))));
                                                            
                                                        set total =amount_department - (amount_department * 0.10);
                                                        
                                                    end if;
                                                    
                                                    RETURN total;
                                                END $$

DELIMITER ;



-- Archivo: sum_commission_specialists.sql
DELIMITER $$

CREATE FUNCTION `sum_commission_specialists`(
            user_id_p int,
            month_p int,
            year_p int,
            module_id_p int
            ) RETURNS decimal(16,2)
BEGIN

            DECLARE total decimal(16,2) default 0;
            DECLARE role_id INT default 0;
            DECLARE sum_specialists decimal(16,2) default 0;

            SELECT um.role_id into role_id FROM user_module um WHERE um.module_id = module_id_p AND um.user_id = user_id_p;

            SELECT IFNULL(SUM(IFNULL(ac.amount,0)),0) INTO sum_specialists
            FROM specialist_commission ac
            WHERE ac.agent_id  = user_id_p
            AND DATE_FORMAT(ac.created_at, "%m") * 1 = month_p
            AND DATE_FORMAT(ac.created_at, "%Y") * 1 = year_p;

            SET total = total + sum_specialists;

            RETURN( total );

        END $$

DELIMITER ;



-- Archivo: sum_commission_v2.sql
DELIMITER $$

CREATE FUNCTION `sum_commission_v2`(id_user int , date_month int , date_year int, type_t int) RETURNS decimal(16,2)
BEGIN
                                            declare amount_user decimal(16,2);
                                            declare id_role int;
                                            declare total decimal(16,2) default 0;
                                            declare amount_department decimal(16,2);
                                            declare amount_ceo decimal(16,2);
                                            declare amount_super decimal(16,2);
                                            declare amount_s_a decimal(16,2);
                                            declare amount_programs decimal(16,2);
                                            declare amount_programs_sup_crm decimal(16,2);
                                            declare commission_super decimal(16,2) default 0;
                                            declare commission_ceo decimal(16,2) default 0;
                                            declare id_sup_crm int;
                                            declare amount_for_ceo_new decimal(16,2);
                                            declare id_sup_module int;

                                            SELECT value into commission_super FROM ced_settings_commission_roles cscr WHERE module_id = 2 and role_id = 2;
                                            SELECT user_id Into id_sup_crm FROM user_module um
                                               JOIN users u ON um.user_id = u.id
                                            WHERE um.module_id = 2 AND um.role_id = 2 and u.status = 1;
                                            SELECT value into commission_ceo FROM ced_settings_commission_roles cscr WHERE role_id = 1;


                                            set commission_super = commission_super / 100;
                                               set commission_ceo = commission_ceo / 100;
                                            set @date_gen = date(concat(date_year,'-',date_month,'-01'));


                                            
                                            DROP TEMPORARY TABLE IF EXISTS temp_amount_department2;
                                            CREATE TEMPORARY TABLE IF NOT EXISTS temp_amount_department2
                                            ENGINE=MEMORY
                                            AS (
                                                SELECT IFNULL(SUM(gcs.amount),0) amount
                                                FROM general_commissions_supervisors gcs where gcs.type_from = 2 and gcs.user_id = id_sup_crm
                                                AND (date(gcs.created_at) >= @date_gen and (date(gcs.created_at) <= last_day(@date_gen)))
                                                AND gcs.status_commission = 1
                                            );

                                            SELECT tad2.amount FROM temp_amount_department2 tad2 INTO amount_department;



                                            
                                                SELECT IFNULL(SUM(gcs.amount),0) into amount_programs_sup_crm
                                                FROM general_commissions_supervisors gcs where gcs.type_from = 1 and gcs.user_id = id_sup_crm
                                                AND (date(gcs.created_at) >= @date_gen and (date(gcs.created_at) <= last_day(@date_gen)))
                                                AND gcs.status_commission = 1;



                                            
                                            DROP TEMPORARY TABLE IF EXISTS temp_amount_ceo;
                                            CREATE TEMPORARY TABLE IF NOT EXISTS temp_amount_ceo
                                            ENGINE=MEMORY
                                            AS (
	                                            SELECT IFNULL(SUM(sc.amount_for_ceo),0) amount
	                                            FROM sales_commissions sc
	                                            WHERE sc.state = 1
	                                            AND (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
                                            );

                                            SELECT tac.amount INTO amount_for_ceo_new FROM temp_amount_ceo tac;



                                            if(type_t = 0) then
                                            

                                            
                                        select IFNULL(SUM(IFNULL(sc.commission,0) - IFNULL(sc.amount_for_sup,0) - IFNULL(sc.amount_for_ceo,0) - IFNULL(sc.amount_for_assist_sup,0)),0),
                                                um.role_id into amount_user, id_role
                                                from sales_commissions sc
                                                    inner join users u on u.id = sc.user_id
                                                    inner join user_module um on um.user_id = u.id
                                                    inner join sales s on s.id = sc.sale_id
                                                where s.type = 0
                                                    and sc.state = 1
                                                    and (um.module_id = 2)
                                                    and (u.id = id_user)
                                                    and (u.status = 1)
                                                    and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
                                                    group by um.role_id;
                                            


                                            
                                                
                                                set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);
                                                
                
                
                
                                                
                                                SELECT ifnull(sum(gcs.amount),0) INTO @comission_crm
                                                FROM general_commissions_supervisors gcs WHERE gcs.user_id = id_user 
                                                AND (date(gcs.created_at) >= @date_gen and (date(gcs.created_at) <= last_day(@date_gen)))
                                                AND gcs.status_commission = 1;
                                            


                                            
                                                set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));

                                                if(id_role = 1)then
                                                    set total = amount_user;
                                                elseif((id_role=2))then
                                                    set total = amount_user  + amount_programs_sup_crm + amount_department;
                                                elseif(@isSupervisorInOtherModule = 1) then
                                                    set total = @comission_crm + amount_user; 
                                                else
                                                    set total = amount_user;
                                                end if;

                                            elseif(type_t = 7) then

                                            
                                                select ifnull(sum(sc.commission * sc.percentage_pay / 100 ),0) , um.role_id into amount_user, id_role
                                                from sales_commissions sc
                                                    inner join users u on u.id = sc.user_id
                                                    inner join user_module um on um.user_id = u.id
                                                    inner join sales s on s.id = sc.sale_id
                                                where s.type = 0
                                                    and sc.state = 1
                                                    and (um.module_id = 2)
                                                    and (u.id = id_user)
                                                    and (u.status = 1)
                                                    and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)))
                                                group by um.role_id;


                                                set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);

                
                
                

                                                SELECT ifnull(sum(gcs.amount),0) INTO @comission_crm
                                                FROM general_commissions_supervisors gcs WHERE gcs.user_id = id_user
                                                AND (date(gcs.created_at) >= @date_gen and (date(gcs.created_at) <= last_day(@date_gen)))
                                                AND gcs.status_commission = 1; 

                                                set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));
                                                if(id_role = 1)then
                                                    set total = amount_user;
                                                elseif( id_role=2 )then
                                                    set total = amount_user  + amount_programs_sup_crm + amount_department;
                                                elseif(@isSupervisorInOtherModule = 1) then
                                                    set total = @comission_crm + amount_user; 
                                                else
                                                    set total = amount_user - (amount_user * (commission_super + commission_ceo));
                                                end if;

                                            elseif(type_t = 1) then

                                                select ifnull(sum(sc.commission),0) into amount_ceo
                                                from sales_commissions sc
                                                    inner join users u on u.id = sc.user_id
                                                    inner join user_module um on um.user_id = u.id
                                                    inner join sales s on s.id = sc.sale_id
                                                where s.type = 0
                                                    and sc.state = 1
                                                    and (um.module_id = 2)
                                                    and (um.role_id = 1)
                                                    and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)));

                                                select ifnull(sum(sc.commission),0) into amount_super
                                                from sales_commissions sc
                                                    inner join users u on u.id = sc.user_id
                                                    inner join user_module um on um.user_id = u.id
                                                    inner join sales s on s.id = sc.sale_id
                                                where s.type = 0
                                                    and sc.state = 1
                                                    and (um.module_id = 2)
                                                    and (um.role_id = 2)
                                                    and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)));
                                                set amount_super = amount_user  + (amount_programs_sup_crm * 0.10) + (amount_department * @commission_super) ;
                                                    if(@is_angela_sup) then
                                                        set amount_super = amount_super +(amount_department * 0.10);
                                                    end if;
                                                set amount_s_a = amount_department - (amount_department * 0.20);
                                                set total = amount_ceo + amount_s_a + amount_super;


                                            elseif(type_t = 2)then
                                            
                                                select ifnull(sum(sc.commission),0) into amount_user
                                                from sales_commissions sc
                                                    inner join users u on u.id = sc.user_id
                                                    inner join user_module um on um.user_id = u.id
                                                    inner join sales s on s.id = sc.sale_id
                                                where s.type = 0
                                                    and sc.state = 1
                                                    and (um.module_id = 2)
                                                    and (u.id = id_user)
                                                    and (u.status = 1)
                                                    and (date(sc.approve_date) >= @date_gen and (date(sc.approve_date) <= last_day(@date_gen)));
                                                set total = amount_user;

                                            elseif(type_t = 8) then

                                                set @isSupervisorInOtherModule = (select exists( select um.role_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.module_id <>2 ));

                                                if(@isSupervisorInOtherModule = 1) then
                                                    
                                                    set @otherModule = (select um.module_id from user_module um where um.user_id = id_user and um.role_id = 2 and um.user_id <> 7 limit 1);

                
                
                

                                                    
                                                    SELECT IFNULL(SUM(gcs.amount),0) INTO @comission_crm
                                                    FROM general_commissions_supervisors gcs
                                                    WHERE gcs.user_id = id_user
                                                    AND (date(gcs.created_at) >= @date_gen and (date(gcs.created_at) <= last_day(@date_gen)))
                                                    AND gcs.status_commission = 1;

                                                    set total = @comission_crm;
                                                else
                                                    set total = 0;
                                                end if;


                                            elseif(type_t = 3) then
                                                
                                                set total = amount_department;

                                            elseif(type_t = 4) then
                                                set total = amount_programs_sup_crm;

                                            elseif(type_t = 5) then
                                                
                                                set total = amount_for_ceo_new;

                                            end if;
                                            return(total);
                                END $$

DELIMITER ;



-- Archivo: sum_module_commission.sql
DELIMITER $$

CREATE FUNCTION `sum_module_commission`(id_user int, date_month int, date_year int, id_type int, id_module int) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    declare amount_user decimal(16,2);
    declare amount_department decimal(16,2);
    declare id_role int;
    declare amount_ceo decimal(16,2);
	declare amount_super decimal(16,2);
    
    select ifnull(sum(mc.commission),0) into amount_department
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			
            and um.role_id not in (1)
            and u.id <> 17
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01');
    
	if(id_type = 0)then 
		
		select ifnull(sum(mc.commission),0), um.role_id into amount_user, id_role
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module            
			and u.id = id_user
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01')
		group by um.role_id;
			
		if(id_role = 1)then
			set total = amount_user;
		elseif(id_role = 2 and id_user = 17)then
			set total = amount_user + (amount_department * 0.20);
		else
			set total = amount_user - (amount_user * 0.20);
        end if;
	elseif(id_type = 1)then 
		
        select ifnull(sum(mc.commission),0) into amount_ceo
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			and um.role_id = 1
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01');
            
		select ifnull(sum(mc.commission),0) into amount_super
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			
            and u.id = 17
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01');
		
        set amount_super = amount_super + (amount_department * 0.20);
        set amount_department = amount_department - (amount_department * 0.20);
		set total = amount_ceo + amount_super + amount_department;
	
    elseif(id_type = 2)then 
		
        select ifnull(sum(mc.commission),0), um.role_id into amount_user, id_role
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module            
			and u.id = id_user
			and (date(mc.created_at) >= date(concat(date_year,'-01-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-12-01')))))
            and (date(mc.created_at) >= '2020-09-01')
		group by um.role_id;
			
		if(id_role = 1)then
			set total = amount_user;
		elseif(id_role = 2 and id_user = 17)then
        
			select ifnull(sum(mc.commission),0) into amount_department
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			
            and um.role_id not in (1)
            and u.id <> 17
			and (date(mc.created_at) >= date(concat(date_year,'-01-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-12-01')))))
            and (date(mc.created_at) >= '2020-09-01');
                
			set total = amount_user + (amount_department * 0.20);
		else
			set total = amount_user - (amount_user * 0.20);
        end if;
	
    elseif(id_type = 3)then 
    
		select ifnull(sum(mc.commission),0) into amount_department
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			and (date(mc.created_at) >= date(concat(date_year,'-01-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-12-01')))))
            and (date(mc.created_at) >= '2020-09-01');
		
        set total = amount_department;
	elseif(id_type = 4)then 
    
		select ifnull(sum(mc.commission),0) into total
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module            
			and u.id = id_user
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01');
            
	elseif(id_type = 5)then 
    
		select ifnull(sum(mc.commission),0) into amount_department
		from modules_commission mc
			inner join users u on u.id = mc.user_id
			inner join user_module um on um.user_id = u.id and um.module_id = id_module
		where mc.module_id = id_module
			
            and um.role_id not in (1)
            and u.id <> 17
			and (date(mc.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(mc.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
            and (date(mc.created_at) >= '2020-09-01');
            
		set total = amount_department * 0.20;
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: sum_paid_users.sql
DELIMITER $$

CREATE FUNCTION `sum_paid_users`(id_program int, id_user int, date_year int, date_month int, id_type int, total_month decimal(16,2)) RETURNS decimal(16,2)
BEGIN
	declare total decimal(16,2);
    declare _date date;
        set _date = date(concat(date_year,'-',date_month,'-01'));
        set @type_automatic := 1;
        set @type_manual := 2;
        set @method_cashier := 7;
        set @modality_monthly := 1;
		SELECT sum( t.amount - ifnull(prt.amount,0) - ifnull(pvt.amount,0) ) into total 
		FROM transactions t
			join client_accounts ca on ca.id = t.client_acount_id
            left join (
				select prt.ref_transaction ,sum(prt.amount) amount from partial_refunds_tranctions prt 
				group by 1
			) prt on  prt.ref_transaction  = t.transaction_id
            left join (
                select pvt.ref_transaction ,sum(pvt.amount) amount from pending_void_transactions pvt 
                group by 1
            ) pvt on  pvt.ref_transaction  = t.transaction_id 
            where t.type_transaction_id in (@type_automatic,@type_manual)
            and not (t.method_transaction_id = @method_cashier and t.modality_transaction_id = @modality_monthly)
		and t.status_transaction_id in (1,5)
        and not t.type_transaction_id  in (16,17)
		and program_id = id_program
		
        and  if(id_user is null , ca.Advisor_id is null, ca.Advisor_id = id_user )
		and t.settlement_date BETWEEN _date and date_add(last_day(_date), interval 1 day);
		

    if(id_type = 0)then 

        set total = (total / total_month) * 100;

    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: sum_sales_p.sql
DELIMITER $$

CREATE FUNCTION `sum_sales_p`( id_user int, date_month int, date_year int, id_type int, id_module int) RETURNS int
BEGIN
	declare total int;
    
    if(id_type = 0)then 
		select count(*) into total
        from sales s
			inner join events e on e.id = s.event_id
        where s.status_id = 4
        and s.type in (1,2)
        and s.module_id = id_module
        and (id_user is null or id_user = 0 or e.Created_users = id_user)
        and (date(s.created_at) >= date(concat(date_year,'-',date_month,'-01')) and (date(s.created_at) <= last_day(date(concat(date_year,'-',date_month,'-01')))))
        and (date(s.created_at) >= '2020-09-01');
        
     elseif(id_type = 1)then 
		select count(*) into total
        from sales s
			inner join events e on e.id = s.event_id
        where s.status_id = 4
        and s.type in (1,2)
        and s.module_id = id_module
        and (id_user is null or id_user = 0 or e.Created_users = id_user)
        and (date(s.created_at) >= date(concat(date_year,'-01-01')) and (date(s.created_at) <= last_day(date(concat(date_year,'-12-01')))))
        and (date(s.created_at) >= '2020-09-01');
    end if;
RETURN total;
END $$

DELIMITER ;



-- Archivo: total_amount_month.sql
DELIMITER $$

CREATE FUNCTION `total_amount_month`(datem date,id_program int,id_advisor int) RETURNS varchar(255) CHARSET latin1
BEGIN
            set @modality_monthly = 1;
            
            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-06');
            SET @last_day_of_month = date_add(date_add(@first_day_of_month,interval -1 day),interval 1 month);
    
            RETURN (select format(sum(ifnull(amount,0)),2) from (select distinct t.id, (ifnull(t.amount,0) - ifnull(prt.amount,0) - ifnull(pvt.amount,0)) amount
                from client_accounts ca
                    inner join accounts_status_histories ash on ash.client_acount_id = ca.id
                    inner join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                    inner join transactions t on t.client_acount_id = ca.id
                    and	t.modality_transaction_id = @modality_monthly
                    and status_transaction_id in (1,5,8)
                    and not t.type_transaction_id in (8,14,16,17)
                    left join (
                        select prt.ref_transaction ,sum(prt.amount) amount from partial_refunds_tranctions prt 
                        group by 1
                    ) prt on  prt.ref_transaction  = t.transaction_id
                    left join (
                        select pvt.ref_transaction ,sum(pvt.amount) amount from pending_void_transactions pvt 
                        group by 1
                    ) pvt on  pvt.ref_transaction  = t.transaction_id
                where 
                    date(ca.created_at) <= DATE_ADD(@first_day_of_month, INTERVAL -6 day) and
                    ((aah.advisor_id = id_advisor or id_advisor = 0 or id_advisor is null)
                            and date(aah.created_at) < @last_day_of_month
                            and (aah.updated_at is null or not aah.updated_at < @last_day_of_month))
                    and (ca.program_id = id_program or id_program = 0 or id_program is null)
                    and ca.migrating = 0 and date(ca.created_at)< @first_day_of_month
                    and date(t.settlement_date) BETWEEN @first_day_of_month and @last_day_of_month
                    and not program_date_for_new_range(ca.program_id, date(t.settlement_date)) 
                    and (
                        (
                            (ash.status in (1,8,9,10) and date(ash.created_at) < @last_day_of_month)
                            or
                            (ash.status in (3,5) and date(ash.created_at) between @first_day_of_month and @last_day_of_month  and t.id is not null  )
                        )
                        and (ash.updated_at is null
                                or not date(ash.updated_at) < @last_day_of_month ))
                group by t.id,2) a);
        END $$

DELIMITER ;



-- Archivo: total_charge.sql
DELIMITER $$

CREATE FUNCTION `total_charge`(`id_account` VARCHAR(36)) RETURNS decimal(16,2)
BEGIN
            RETURN (
                SELECT SUM(amount)
                FROM (
                    (SELECT 'fee' AS type, s.fee_amount AS amount, ca.created_at
                    FROM sales s
                    INNER JOIN client_accounts ca 
                        ON ca.client_id = s.client_id 
                        AND ca.program_id = s.program_id
                    WHERE ca.id = id_account)
                    
                    UNION
                    
                    (SELECT ac.charge AS type, ac.amount, ac.created_at
                    FROM additional_charges ac
                    LEFT JOIN transactions t 
                        ON t.id = ac.transactions_id
                    WHERE ac.client_acount_id = id_account 
                        AND ac.deleted_at IS NULL
                        AND ac.state_charge = 1 
                        AND (t.type_transaction_id NOT IN (10, 11) OR t.type_transaction_id IS NULL)
                    )
                ) AS tc
            );
        END $$

DELIMITER ;



-- Archivo: total_client_expenses.sql
DELIMITER $$

CREATE FUNCTION `total_client_expenses`(
            p_account_id varchar(36)
        ) RETURNS decimal(16,2)
BEGIN
            declare v_total_expense decimal(16,2);

            select coalesce(sum(ce.amount), 0) into v_total_expense from client_expenses ce
                join department_expenses de on ce.department_expense_id = de.id
                and ce.client_account_id = p_account_id and ce.status = 'CONFIRMED';
            return v_total_expense;
        END $$

DELIMITER ;



-- Archivo: total_department_expenses.sql
DELIMITER $$

CREATE FUNCTION `total_department_expenses`(
            p_month int,
            p_year int,
            p_module_id int
        ) RETURNS decimal(10,2)
BEGIN
            declare v_total_department_expenses decimal(10,2);
            SELECT coalesce(SUM(amount), 0) into v_total_department_expenses FROM 
                (
                    SELECT coalesce(de.amount, 0) amount
                    FROM department_expenses de
                    JOIN credit_card_expenses cce ON de.credit_card_expense_id = cce.id
                    
                    WHERE status_expense_id = 1
                        AND method = 'CREDIT_CARD'
                        and month(`date`) = p_month and year(`date`) = p_year
                        and if(p_module_id is null, true, de.module_id = p_module_id)
                    
                    
                    
                    
                    
                    
                    
                    
                    
                ) AS combined_amounts;
            return v_total_department_expenses;
        END $$

DELIMITER ;



-- Archivo: total_payment.sql
DELIMITER $$

CREATE FUNCTION `total_payment`(id_account varchar(36)) RETURNS decimal(16,2)
BEGIN
        declare id_sale int;
        declare total_positive_amount decimal(11,2);
        declare total_negative_amount decimal(11,2);
        declare total_negative_amount_partials decimal(10,2);
        declare total decimal(11,2);
        set @type_automatic := 1;
        set @type_manual := 2;
        set @type_others := 6;
        set @type_credit := 8;
        set @type_pfy := 9;
        set @type_void := 10;
        set @type_refund := 11;
        set @type_charge_back := 15;
        set @type_partial_void :=16;
        set @type_partial_refund :=17;
        set @modality_penalty := 5;
        set @modality_return := 6;
        set @modality_penalty_return := 7;

        SELECT ip.sale_id into id_sale FROM client_accounts ca
            inner join initial_payments ip on ip.account = ca.account
        where ca.id=id_account;

        set total_positive_amount = (select sum(amount)
            from ((select t.settlement_date,t.id,t.amount,'Initial payment' type
                    from transactions t
                        inner join initial_payments ip on ip.sale_id = t.sale_id
                        inner join client_accounts ca on ip.account = ca.account
                    where  t.sale_id = id_sale
                    and t.type_transaction_id not in (@type_void,@type_refund,@type_partial_void,@type_partial_refund)
                    and status_transaction_id in (1,5))
                    union
                    (select t.settlement_date,t.id,t.amount,'Initial payment' type
                    from transactions t
                        inner join initial_payments ip on ip.transactions_id = t.id
                        inner join client_accounts ca on ip.account = ca.account
                    where ca.id = id_account
                    and t.type_transaction_id not in (@type_void,@type_refund)
                    and status_transaction_id in (1,5))
                    union
                    (select t.settlement_date,t.id,t.amount,'Monthly payment' type
                    from transactions t
                    where t.status_transaction_id in (1,5)
                        and t.type_transaction_id in (@type_automatic,@type_manual,@type_credit)
                        and t.client_acount_id = id_account)
                    union
                    (select t.settlement_date,t.id,t.amount,ac.charge type
                    from transactions t
                        inner join additional_charges ac on ac.transactions_id = t.id
                    where ac.client_acount_id = id_account
                    and t.type_transaction_id not in (@type_void,@type_refund)
                    and ac.charge_indicator = 1
                    and status_transaction_id in (1,5))
                    union
                    (select t.settlement_date,t.id,t.amount,'Payments of year ' type
                    from transactions t
                    where (t.type_transaction_id = @type_pfy and t.method_transaction_id is null and t.modality_transaction_id is null)
                    and t.client_acount_id = id_account
                    and status_transaction_id in (1,5))
                    union
                    (select t.settlement_date,t.id,t.amount,'Others' type
                    from transactions t
                    where t.status_transaction_id in (1,5)
                        and t.type_transaction_id in (@type_others)
                        and t.sale_id is null
                        and t.client_acount_id = id_account
                        AND NOT EXISTS (
                            SELECT 1 
                            FROM additional_charges ac 
                            WHERE ac.transactions_id = t.id
                        ))
                    union
                    (select t.settlement_date,t.id,t.amount,'Charge back ' type
                    from transactions t
                    where t.type_transaction_id = @type_charge_back and t.method_transaction_id is null and (modality_transaction_id = @modality_penalty_return or modality_transaction_id = @modality_return)
                    and t.client_acount_id = id_account
                    and status_transaction_id in (1,5,9))) p);

        set total_negative_amount = (select sum(amount)
            from ((select t.settlement_date,t.id,t.amount,'Charge back' type
                    from transactions t
                    where type_transaction_id = @type_charge_back  and method_transaction_id is null and (modality_transaction_id = @modality_penalty or modality_transaction_id is null)
                    and t.client_acount_id = id_account
                    and status_transaction_id in (1,5,9))) p);

        set total_negative_amount_partials=(select sum(amount)
        from((select  t.settlement_date,t.id,t.amount,'Partial Void/Refund' type
            from transactions t
            where type_transaction_id in (@type_partial_void,@type_partial_refund)
            and t.client_acount_id=id_account
            and status_transaction_id in(1,5,9)))p);

        set total = (select total_positive_amount - ifnull(total_negative_amount,0)-ifnull(total_negative_amount_partials,0));
        return total;
        END $$

DELIMITER ;



-- Archivo: total_remaining_month.sql
DELIMITER $$

CREATE FUNCTION `total_remaining_month`(datem date,id_program int,id_advisor int) RETURNS varchar(255) CHARSET utf8mb3
BEGIN
        set @type_automatic = 1;
            set @type_manual = 2;
            set @type_zero = 14;

            
            set @method_card = 1;
            set @method_cash = 2;
            set @method_cashier = 7;

            
            set @modality_monthly = 1;
        
            SET @first_day_of_month = DATE_FORMAT(datem, '%Y-%m-06');
            SET @last_day_of_month =  date_add(@first_day_of_month,interval 1 month) ;
            SET @new_last_day_of_month = LAST_DAY(@first_day_of_month);
            SET @C_PARAGON_PROGRAM = 9;

            RETURN (
                SELECT
                    format(sum(amount),2)
                from (
                    SELECT
                        get_last_recurring_billing_amount_in_range( ca.id, @first_day_of_month, @last_day_of_month ) amount
                    from client_accounts ca
                        inner join accounts_status_histories ash on ash.client_acount_id = ca.id
                        inner join accounts_advisors_histories aah on aah.client_acount_id = ca.id
                        inner join recurring_billings rb on rb.client_acount_id = ca.id 
                        left join transactions t on t.client_acount_id = ca.id and t.status_transaction_id in (1,5,8)
                        and not t.type_transaction_id  in (8,14,16,17)
                        and t.modality_transaction_id = @modality_monthly
                        and  t.settlement_date >= @first_day_of_month 
                        AND t.settlement_date < IF(program_date_for_new_range(ca.program_id,t.settlement_date), @new_last_day_of_month, @last_day_of_month)
                        AND NOT program_date_for_new_range(ca.program_id,t.settlement_date)
                    where date(ca.created_at) <= DATE_ADD(@first_day_of_month, INTERVAL -6 day)
                    and ((aah.advisor_id = id_advisor or id_advisor = 0 or id_advisor is null)
                    and aah.created_at < @last_day_of_month
                    and (aah.updated_at is null or not aah.updated_at < @last_day_of_month  ))
                    and (ca.program_id = id_program or id_program = 0 or id_program is null)
                    AND ca.program_id NOT IN ( @C_PARAGON_PROGRAM )  
                    AND NOT program_date_for_new_range(ca.program_id,@first_day_of_month)
                    and ca.migrating = 0 and (date(ca.created_at)< @first_day_of_month or account_paid(ca.id, @first_day_of_month ))
                    and t.id is NULL 
                    and (
                            (
                                (ash.status in (1,8,9,10) and ash.created_at < @last_day_of_month )
                                OR
                                (ash.status in (3,5) and ash.created_at >= @first_day_of_month and ash.created_at < @last_day_of_month  and t.id is not null  )
                            )
                        AND (ash.updated_at IS NULL OR NOT ash.updated_at <= if(program_date_for_new_range(ca.program_id,t.settlement_date), @new_last_day_of_month , @last_day_of_month )) 
                        ) 
                ) a 
            ); 
        END $$

DELIMITER ;



-- Archivo: users_list.sql
DELIMITER $$

CREATE FUNCTION `users_list`(`id_list` INT) RETURNS json
BEGIN
            
            RETURN (select JSON_ARRAYAGG(a) from (select JSON_OBJECT('id',gu.user_id,'user_name',concat(u.first_name,' ',u.last_name),'done',sum(gl.status)) a
                        from group_users gu 
                            inner join users u on u.id = gu.user_id
                            inner join group_lists gl on gl.user_id = gu.user_id and gl.listuser_id = gu.listuser_id
                        where gu.listuser_id =id_list
                        group by gu.listuser_id,gu.user_id) a);
            END $$

DELIMITER ;



-- Archivo: working_days_calculator.sql
DELIMITER $$

CREATE FUNCTION `working_days_calculator`(
            `start_date` date,
            qty_days int
        ) RETURNS date
BEGIN
            
            declare final_date date;
            declare day_of_week int;
            declare i int default 0;

            set final_date = start_date;
            while i < qty_days do
                set final_date = date_add(final_date, interval 1 day);
                set day_of_week = dayofweek(final_date);
                if(day_of_week != 1 and day_of_week != 7 and
                    not exists (
                        SELECT 1 FROM attendance_holidays WHERE `day` = DAY(final_date)
                        AND `month` = MONTH(final_date) AND (`repeat` = 1 or (`repeat` = 0 and `year` = year(final_date)))
                    )
                ) then
                    set i = i + 1;
                end if;
            end while;

            return final_date;
        END $$

DELIMITER ;



