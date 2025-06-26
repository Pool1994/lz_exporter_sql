-- Archivo: change_statuses_trigger.sql
DELIMITER $$

CREATE TRIGGER `change_statuses_trigger` AFTER INSERT ON `user_session_statusses_tracking` FOR EACH ROW BEGIN
            IF NEW.user_session_statuses_id = 1 THEN
                UPDATE user_module AS u 
                JOIN modules AS m
                ON u.module_id  = m.id
                SET u.user_session_statuses_id = 4 
                WHERE u.user_id = NEW.created_by AND u.module_id != NEW.module_id AND m.parent_id = 21;
            END IF;
        END $$

DELIMITER ;



-- Archivo: check_zero_payments.sql
DELIMITER $$

CREATE TRIGGER `check_zero_payments` AFTER UPDATE ON `transactions` FOR EACH ROW BEGIN
            DECLARE _i INT DEFAULT 0;
            DECLARE _all_zero_payment INT DEFAULT 1;
            DECLARE _is_in_status_active INT DEFAULT 0;
            DECLARE _program_id INT;

            IF OLD.status_transaction_id != 1 AND NEW.type_transaction_id = 14 AND NEW.status_transaction_id = 1 THEN
                WHILE _all_zero_payment = 1 AND _i <= 2 DO
                    SELECT IF(COUNT(*) > 0, 1, 0) INTO _all_zero_payment FROM transactions t
                        WHERE t.client_acount_id = NEW.client_acount_id
                          AND DATE_FORMAT(t.settlement_date, '%Y-%m') = DATE_FORMAT(DATE_ADD(NEW.settlement_date, INTERVAL -_i MONTH), '%Y-%m')
                          AND t.type_transaction_id = 14 AND t.modality_transaction_id = 1 AND t.method_transaction_id is null AND t.status_transaction_id = 1;
                    SET _i = _i + 1;
                END WHILE;
            ELSE
                SET _all_zero_payment = 0;
            END IF;

            IF _all_zero_payment = 1 THEN
                SELECT status,program_id INTO _is_in_status_active,_program_id
                FROM client_accounts WHERE id = NEW.client_acount_id;

                IF _is_in_status_active = 1 THEN
                    UPDATE client_accounts SET status = 2
                    WHERE id = NEW.client_acount_id;
                    UPDATE accounts_status_histories SET updated_at  = now(), updater_id = 0
                    WHERE client_acount_id = NEW.client_acount_id and updated_at is null;
                    insert into accounts_status_histories (id, client_acount_id, status, user_id, created_at)
                    values (uuid(), NEW.client_acount_id, 2, 0, now());

                    IF _program_id = 3 THEN

                        
                        CALL sp_send_client_to_connection(
                            (SELECT client_id FROM client_accounts WHERE id = NEW.client_acount_id),
                            NEW.client_acount_id,
                            'CONNECTION',
                            'HOLD',
                            'OTHERS',
                            0,
                            '',
                            NEW.user_id,
                            null);

                    END IF;

                END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_all_fee_commission_for_financial_x.sql
DELIMITER $$

CREATE TRIGGER `generate_all_fee_commission_for_financial_x` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN

        
        set @type_automatic = 1;
        set @type_manual = 2;

        
        set @method_cashier = 7;
        
        set @modality_monthly = 1;
		IF (NEW.status_transaction_id IN (1,5)
            AND (select program_id from client_accounts ca
            WHERE id = NEW.client_acount_id)=3
            AND (NEW.type_transaction_id IN(@type_automatic,@type_manual)
                 and not ( NEW.type_transaction_id = @type_manual and NEW.method_transaction_id = @method_cashier and NEW.modality_transaction_id = @modality_monthly))
            AND (NEW.id_payments_type BETWEEN 1 AND 6)
            AND ((select role_id from user_module where user_id = NEW.user_id AND module_id=23) in (14,15))
            AND (NEW.amount >= (SELECT cas.total_charged - cas.total_payment FROM client_balance_financial cas where client_account_id = NEW.client_acount_id))
            AND NEW.amount >= (SELECT amount FROM ced_setting_commission_type csct2 WHERE slug='all-fee')
            )
            THEN
                CALL create_commission_ced((SELECT id FROM ced_setting_commission_type csct where slug = 'all-fee'),NEW.amount,23,null,NEW.user_id,
                NEW.client_acount_id);
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_insert.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_insert` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN
            IF (NEW.status_transaction_id IN (1,5,9)
            AND (select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=3)
            THEN
                update client_balance_financial 
                set total_payment = total_payment(NEW.client_acount_id),total_charged =
				total_charge(client_account_id) where client_account_id =NEW.client_acount_id;
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_insert_additional_charge.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_insert_additional_charge` AFTER INSERT ON `additional_charges` FOR EACH ROW BEGIN
            IF ((select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=3)
            THEN
                update client_balance_financial
                set total_payment = total_payment(NEW.client_acount_id),total_charged =
				total_charge(NEW.client_acount_id) where client_account_id =NEW.client_acount_id;
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_insert_initial_payment.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_insert_initial_payment` AFTER INSERT ON `initial_payments` FOR EACH ROW BEGIN
            IF ((select program_id from client_accounts ca WHERE account = NEW.account)=3)
            THEN

                update client_balance_financial
                set total_payment = total_payment((select id from client_accounts ca WHERE account = NEW.account)),total_charged =
				total_charge((select id from client_accounts ca WHERE account = NEW.account)) where client_account_id =(select id from client_accounts ca WHERE account = NEW.account);
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_update.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_update` AFTER UPDATE ON `transactions` FOR EACH ROW BEGIN
        IF (NEW.status_transaction_id IN (1,5,9)
        AND (select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=3)
        THEN
            update client_balance_financial 
            set total_payment = total_payment(NEW.client_acount_id),total_charged =
            total_charge(client_account_id) where client_account_id =NEW.client_acount_id;
        END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_update_additional_charge.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_update_additional_charge` AFTER UPDATE ON `additional_charges` FOR EACH ROW BEGIN
            IF ((select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=3)
            THEN
                update client_balance_financial
                set total_payment = total_payment(NEW.client_acount_id),total_charged =
				total_charge(NEW.client_acount_id) where client_account_id =NEW.client_acount_id;
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_client_on_update_initial_payment.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_client_on_update_initial_payment` AFTER UPDATE ON `initial_payments` FOR EACH ROW BEGIN
            IF ((select program_id from client_accounts ca WHERE account = NEW.account)=3)
            THEN

                update client_balance_financial
                set total_payment = total_payment((select id from client_accounts ca WHERE account = NEW.account)),total_charged =
				total_charge((select id from client_accounts ca WHERE account = NEW.account)) where client_account_id =(select id from client_accounts ca WHERE account = NEW.account);
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_ds_client_on_insert.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_ds_client_on_insert` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN
            IF (NEW.status_transaction_id IN (1,5)
            AND (select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=4)
            THEN
                update ds_clients_ad
                set available_balance = (total_payment(NEW.client_acount_id) -
				total_charge(NEW.client_acount_id)) where client_id = (select client_id from client_accounts ca2 where ca2.id = NEW.client_acount_id );
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_balance_for_ds_client_on_update.sql
DELIMITER $$

CREATE TRIGGER `generate_balance_for_ds_client_on_update` AFTER UPDATE ON `transactions` FOR EACH ROW BEGIN
            IF (NEW.status_transaction_id IN (1,5)
            AND (select program_id from client_accounts ca WHERE id = NEW.client_acount_id)=4)
            THEN
                update ds_clients_ad
                set available_balance = (total_payment(NEW.client_acount_id) -
				total_charge(NEW.client_acount_id)) where client_id = (select client_id from client_accounts ca2 where ca2.id = NEW.client_acount_id );
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_commission_for_financial_x.sql
DELIMITER $$

CREATE TRIGGER `generate_commission_for_financial_x` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN

        
        set @type_automatic = 1;
        set @type_manual = 2;

        
        set @method_cashier = 7;

        
        set @modality_monthly = 1;

		    IF (NEW.status_transaction_id IN (1,5)
            AND (select program_id from client_accounts ca
            WHERE id = NEW.client_acount_id)=3
            AND (NEW.type_transaction_id IN(@type_automatic,@type_manual)
                 and not ( NEW.type_transaction_id = @type_manual and NEW.method_transaction_id = @method_cashier and NEW.modality_transaction_id = @modality_monthly))
            AND NEW.id_payments_type in (1,2,4,5,6)
            AND ((select role_id from user_module where user_id = NEW.user_id AND module_id=23) in (14,15)))
            THEN
                CALL create_commission_ced((select fn_payment_type_id_to_commission_id(NEW.id_payments_type)),NEW.amount,23,null,NEW.user_id,
                NEW.client_acount_id);
            END IF;
        END $$

DELIMITER ;



-- Archivo: generate_history_ds_analysis_credits.sql
DELIMITER $$

CREATE TRIGGER `generate_history_ds_analysis_credits` BEFORE UPDATE ON `ds_analysis_credits` FOR EACH ROW begin
	    	INSERT INTO history_ds_analysis_credits
			(ds_analysis_credit_id, client_id, event_id, c_name, c_middle, c_last, c_dob, c_ssn, street, city, zipcode, country, states, c_status_lead, status_civil,
			c_status_civil, dependents, c_dependents, employer, c_employer, c_phone_work, applicant_monthly, c_applicant_monthly, adicional_monthly, housing, monthly_payment, 
			utilites, telephone, food, insurance, car_payment, car_payment_2, car_payment_3, car_payment_4, car_payment_5, gasoline, others_t, others_m, goal1, date_g1, goal2,
			date_g2, goal3, date_g3, goal4, date_g4, `type`, remunerated, payment_date, type_payment, json_utility, json_montutility, json_others, json_montothers, created_at, created_by)
			values 
			( old.id, old.client_id, old.event_id, old.c_name, old.c_middle, old.c_last, old.c_dob, old.c_ssn, old.street, old.city, old.zipcode, old.country, old.states,
		    old.c_status_lead, old.status_civil, old.c_status_civil, old.dependents, old.c_dependents, old.employer, old.c_employer, old.c_phone_work, old.applicant_monthly,
		    old.c_applicant_monthly, old.adicional_monthly, old.housing, old.monthly_payment, old.utilites, old.telephone, old.food, old.insurance, old.car_payment, old.car_payment_2,
		    old.car_payment_3, old.car_payment_4, old.car_payment_5, old.gasoline, old.others_t, old.others_m, old.goal1, old.date_g1, old.goal2, old.date_g2, old.goal3, old.date_g3, 
		   old.goal4, old.date_g4, old.`type`, old.remunerated, old.payment_date, old.type_payment, old.json_utility, old.json_montutility, old.json_others, old.json_montothers,now(), old.created_by);
        end $$

DELIMITER ;



-- Archivo: generate_payment_schedule_for_new_or_existing_clients.sql
DELIMITER $$

CREATE TRIGGER `generate_payment_schedule_for_new_or_existing_clients` AFTER UPDATE ON `sales` FOR EACH ROW BEGIN
            DECLARE client_account_id CHAR(36);
            
            IF NEW.client_id IS NOT NULL AND FIND_IN_SET(NEW.program_id, programs_with_new_schedule(date(now()))) > 0 AND NEW.status_id = 4 AND NEW.annulled_at IS NULL THEN
               SELECT ca.id INTO client_account_id   from  client_accounts ca where ca.client_id = NEW.client_id and ca.program_id = NEW.program_id;
               IF client_account_id IS NOT NULL THEN
                   CALL generate_payment_schedule_for_new_or_existing_clients(client_account_id, NEW.program_id, 1);
               END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: inser_last_note_account.sql
DELIMITER $$

CREATE TRIGGER `inser_last_note_account` AFTER INSERT ON `notes_accounts` FOR EACH ROW BEGIN
	        set @program_id = (select ca.program_id from client_accounts ca where ca.id = NEW.client_account_id);
            IF exists(select * from client_account_last_notes caln where caln.client_account_id = NEW.client_account_id and caln.type = NEW.type ) THEN
                UPDATE client_account_last_notes set note_account_id = NEW.id, content = NEW.content, date = NEW.date, type = NEW.type, updated_at = now()
                where client_account_id = NEW.client_account_id and type = NEW.type;
            ELSE
            	insert into client_account_last_notes (client_account_id, note_account_id, content, date, type, program_id, created_at)					
				values (NEW.client_account_id, NEW.id, NEW.content, NEW.date, NEW.type, @program_id, now());
            END IF;
        END $$

DELIMITER ;



-- Archivo: insert_client_account_timeline.sql
DELIMITER $$

CREATE TRIGGER `insert_client_account_timeline` AFTER INSERT ON `client_accounts` FOR EACH ROW BEGIN 
            IF (NEW.program_id = 4) THEN
            INSERT INTO client_account_timeline (client_account_id, created_at, updated_at, generated_timeline)
            VALUES (NEW.id, now(), null, false);
            END IF;
        END $$

DELIMITER ;



-- Archivo: insert_client_to_balance_finantial.sql
DELIMITER $$

CREATE TRIGGER `insert_client_to_balance_finantial` AFTER INSERT ON `client_accounts` FOR EACH ROW BEGIN
            IF NEW.program_id=3 THEN
            	INSERT INTO client_balance_financial (client_account_id, total_payment, total_charged, created_at)
				VALUES(NEW.id, total_payment(NEW.id), total_charge(NEW.id), NOW());
            END IF;
        END $$

DELIMITER ;



-- Archivo: insert_end_and_start_date_client_ds_timeline.sql
DELIMITER $$

CREATE TRIGGER `insert_end_and_start_date_client_ds_timeline` AFTER UPDATE ON `sales` FOR EACH ROW begin
            if (new.program_id = 4 and new.status_id=4 and new.annul =0 and new.annulled_at is null) then
                call sp_insert_end_and_start_date_client_ds_timeline(new.id);
            end if;
        end $$

DELIMITER ;



-- Archivo: process_additional_charges_in_payment_schedule.sql
DELIMITER $$

CREATE TRIGGER `process_additional_charges_in_payment_schedule` AFTER INSERT ON `additional_charges` FOR EACH ROW BEGIN
            DECLARE _program_id INT DEFAULT NULL;
	        DECLARE _status INT DEFAULT NULL;
	        SET @type_charge = 7;
    		SET @modality_charge = 4;
    	    SET @loyal_in_progress = 11;
    	    SET @loyal_potential = 12;
    	    SET @loyal_stand_by = 13;
    	    SET @active_current = 8;
    	   	SET @mode = 5;
    	   	SET @modality_monthly = 1;
    	    SET @type_transaction_manual = 2;
	       	
	       	SELECT program_id, status INTO _program_id, _status FROM client_accounts ca where id = NEW.client_acount_id;
            SET @has_payment_schedule := (SELECT MAX(id) FROM payment_schedule where client_account_id = NEW.client_acount_id and is_active = 1);
     
    		IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 AND @has_payment_schedule IS NOT NULL AND NEW.idcreditor IS NULL THEN
            	
	            IF NEW.transactions_id IS NULL AND NEW.from_op = 0 AND NEW.state_charge = 1 THEN
	               IF _status IN(@loyal_in_progress, @loyal_potential, @loyal_stand_by) THEN
	               		INSERT IGNORE INTO temp_client_accounts(client_acount_id, new_status) VALUES(NEW.client_acount_id, @active_current);
	               		SET @mode = 10;
	               END IF;
	               
	               	INSERT INTO charge_schedules(charge_id, payment_schedule_id, amount, created_at) VALUES(NEW.id, @has_payment_schedule, NEW.amount, now());
	                CALL recalculate_payment_schedule_by_clients_ce(NEW.client_acount_id, 4, @has_payment_schedule, _program_id, @mode);
	               
	            END IF;
	        
	            
	            IF NEW.transactions_id IS NOT NULL AND NEW.state_charge = 1 THEN
	                SELECT COALESCE((ac.amount - t.amount),0), t.amount 
	                INTO @pending_amount, @amount_paid
	                FROM additional_charges ac
	                JOIN transactions t ON t.id = ac.transactions_id
	                WHERE ac.transactions_id = NEW.transactions_id
	                AND t.status_transaction_id IN(1,5,8)
	               	AND t.type_transaction_id  = @type_charge
	        		AND t.modality_transaction_id = @modality_charge;
	            
	                IF @pending_amount > 0 THEN
	                    IF _status IN(@loyal_in_progress, @loyal_potential, @loyal_stand_by) THEN
		               		SET @mode = 11;
		                END IF;
		               
	                   	INSERT INTO charge_schedules(charge_id, payment_schedule_id, amount, created_at) VALUES(NEW.id, @has_payment_schedule, @pending_amount, now());
	                	CALL recalculate_payment_schedule_by_clients_ce(NEW.client_acount_id, 4, @has_payment_schedule, _program_id, @mode);
	                
						IF _status IN(@loyal_in_progress, @loyal_potential, @loyal_stand_by) THEN
		               		UPDATE transactions SET modality_transaction_id = @modality_monthly, type_transaction_id = @type_transaction_manual WHERE id = NEW.transactions_id;
		               		INSERT IGNORE INTO temp_client_accounts(client_acount_id, new_status) VALUES(NEW.client_acount_id, @active_current);
		                END IF;
	                   
	                END IF;
	            END IF;
	           
	           
	           IF NEW.transactions_id IS NOT NULL AND NEW.state_charge = 1 THEN
	           		SET @isPartialPaid := (SELECT ac.id
											FROM additional_charges ac
											JOIN transactions t ON t.id = ac.transactions_id
											WHERE ac.transactions_id = NEW.transactions_id
											AND t.status_transaction_id IN(1,5,8) 
											AND ac.state_charge = 1
											AND t.type_transaction_id  = @type_charge
											AND t.modality_transaction_id = @modality_charge
											AND ac.partial_group IS NOT NULL);
					IF @isPartialPaid IS NOT NULL THEN
						DELETE FROM  charge_schedules WHERE payment_schedule_id = @has_payment_schedule;
						CALL migration_additional_charges_payment_schedule(@has_payment_schedule, NEW.client_acount_id, _program_id, NULL);   	
					END IF;
	           END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: process_additional_charges_in_payment_schedule_update.sql
DELIMITER $$

CREATE TRIGGER `process_additional_charges_in_payment_schedule_update` AFTER UPDATE ON `additional_charges` FOR EACH ROW BEGIN
            DECLARE _program_id INT DEFAULT NULL;
	        DECLARE _status INT DEFAULT NULL;
	        SET @type_charge = 7;
    		SET @modality_charge = 4;
    		SET @loyal_in_progress = 11;
    	    SET @loyal_potential = 12;
    	    SET @loyal_stand_by = 13;
    	    SET @mode = 5;
    	   	SET @modality_monthly = 1;
    	    SET @type_transaction_manual = 2;
	       	
	       	SELECT program_id, status INTO _program_id, _status FROM client_accounts ca where id = NEW.client_acount_id;
            SET @has_payment_schedule := (SELECT MAX(id) FROM payment_schedule where client_account_id = NEW.client_acount_id and is_active = 1);
            
	        IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 AND @has_payment_schedule IS NOT NULL AND NEW.idcreditor IS NULL THEN
    			
	            IF NEW.transactions_id IS NOT NULL AND NEW.from_op = 1 AND NEW.state_charge = 1  THEN
	                SELECT COALESCE((ac.amount - t.amount),0)  
	                INTO @pending_amount 
	                FROM additional_charges ac
	                JOIN transactions t ON t.id = ac.transactions_id
	                WHERE ac.transactions_id = NEW.transactions_id
	                AND t.status_transaction_id IN(1,5,8)
	                AND t.type_transaction_id  = @type_charge
	        		AND t.modality_transaction_id = @modality_charge;
	            
	                IF @pending_amount > 0 THEN
	                    IF _status IN(@loyal_in_progress, @loyal_potential, @loyal_stand_by) THEN
		               		SET @mode = 11;
		                END IF;
	                
                   		INSERT INTO charge_schedules(charge_id, payment_schedule_id, amount, created_at) VALUES(NEW.id, @has_payment_schedule, @pending_amount, now());
		                CALL recalculate_payment_schedule_by_clients_ce(NEW.client_acount_id, 4, @has_payment_schedule, _program_id, @mode);
		               
		               	IF _status IN(@loyal_in_progress, @loyal_potential, @loyal_stand_by) THEN
		               		UPDATE transactions SET modality_transaction_id = @modality_monthly, type_transaction_id = @type_transaction_manual WHERE id = NEW.transactions_id;
		               		INSERT IGNORE INTO temp_client_accounts(client_acount_id, new_status) VALUES(NEW.client_acount_id, @active_current);
		                END IF;
	                   
	                END IF;
	            END IF;
	       END IF;
        END $$

DELIMITER ;



-- Archivo: process_payment_schedule_ce.sql
DELIMITER $$

CREATE TRIGGER `process_payment_schedule_ce` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN
        	DECLARE current_status INT;
	       	DECLARE _program_id INT;
	       	DECLARE _client_type INT;
	       	
	       	set @type_void = 10;
           	set @type_refund = 11;
           	set @type_void_parcial=16;
           	set @type_refund_parcial=17;
           	SET @type_credit = 8;
           	set @modality_monthly = 1;
            SET @status_hold = 2;
           	SET @client_type_regular = 1;
           	SET @boostcredit_program_id = 2;
                    
	        SELECT `status`, program_id, client_type_id INTO current_status, _program_id, _client_type from client_accounts where id =  NEW.client_acount_id;
	       
	       	IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
	       
		       	SET @payment_schedule_id := (SELECT MAX(ps.id) from payment_schedule ps WHERE ps.client_account_id = NEW.client_acount_id AND ps.is_active = 1);
		       	
	            IF NEW.modality_transaction_id = @modality_monthly  AND NEW.status_transaction_id IN (5,8,1) AND NEW.type_transaction_id NOT IN(@type_void,@type_refund,@type_void_parcial,@type_refund_parcial,@type_credit) THEN
	
					CALL ce_update_payment_schedule_by_client(NEW.id, NEW.type_transaction_id, _program_id);
					
					IF _program_id = @boostcredit_program_id AND @payment_schedule_id IS NOT NULL THEN 
						CALL recalculate_payment_schedule_by_clients_ce(NEW.client_acount_id, 4, @payment_schedule_id, _program_id, 14);
					END IF;
	
	            END IF;
			 
			 	
				 IF NEW.type_transaction_id = @type_credit AND NEW.status_transaction_id IN (5,8,1) THEN
				 	IF @payment_schedule_id IS NOT NULL THEN
				 		CALL recalculate_payment_schedule_by_clients_ce(NEW.client_acount_id, 4, @payment_schedule_id, _program_id, 9);
				 	END IF;
				 END IF;
			END IF;
        END $$

DELIMITER ;



-- Archivo: process_payment_schedule_update.sql
DELIMITER $$

CREATE TRIGGER `process_payment_schedule_update` AFTER UPDATE ON `transactions` FOR EACH ROW BEGIN 
			DECLARE _program_id INT;
			set @type_void = 10;
			set @type_refund = 11;
			set @modality_monthly = 1;
			set @mode_void = 2;
			set @mode_refund = 3;
			set @mode_declined = 1;
			
			SET @type_charge = 7;
			SET @modality_charge = 4;
		
			SET @type_transaction_manual = 2;
		
			SELECT program_id INTO _program_id from client_accounts where id =  NEW.client_acount_id;
		
			IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
			
				IF OLD.modality_transaction_id = @modality_monthly  AND NEW.status_transaction_id = 2 AND OLD.status_transaction_id = 1 THEN
					CALL payment_schedule_reimbursement(NEW.id, @mode_declined); 
				END IF;
				
				IF OLD.modality_transaction_id = @modality_monthly AND OLD.status_transaction_id IN(1,5,8) AND NEW.type_transaction_id = @type_void THEN
					CALL payment_schedule_reimbursement(NEW.id, @mode_void);
				END IF;
				
				IF OLD.modality_transaction_id = @modality_monthly AND OLD.status_transaction_id IN(1,5,8) AND NEW.type_transaction_id = @type_refund THEN
						CALL payment_schedule_reimbursement(NEW.id, @mode_refund);
				END IF;    
	
				
				IF OLD.modality_transaction_id = @modality_charge AND OLD.status_transaction_id IN(1,5,8) AND OLD.type_transaction_id = @type_charge AND NEW.type_transaction_id IN(@type_void, @type_refund) THEN
						SELECT ac.id, t.amount, ps.id, ca.program_id
						INTO @charge_id, @amount, @payment_schedule_id, @program_id
						FROM additional_charges ac
						JOIN transactions t ON t.id = ac.transactions_id
						JOIN payment_schedule ps on ps.client_account_id = t.client_acount_id
						JOIN client_accounts ca ON ca.id = ps.client_account_id
						WHERE ac.transactions_id = OLD.id
						AND t.status_transaction_id IN(1,5,8)
						AND t.type_transaction_id  IN(@type_void, @type_refund)
						AND ps.is_active = 1
						AND ps.id = (SELECT MAX(id) FROM payment_schedule WHERE client_account_id = t.client_acount_id  AND is_active = 1)
						AND ac.state_charge = 1;
					
					IF @payment_schedule_id IS NOT NULL THEN
						CALL recalculate_payment_schedule_by_clients_ce(OLD.client_acount_id, 4, @payment_schedule_id, @program_id, 6);
					END IF;
				END IF;  
			
				IF OLD.modality_transaction_id = @modality_charge AND NEW.modality_transaction_id = @modality_monthly AND OLD.type_transaction_id = @type_charge AND NEW.type_transaction_id = @type_transaction_manual
					AND NEW.status_transaction_id IN(1,5,8) THEN
					
					SET @payment_schedule_id = (SELECT MAX(ps.id) FROM payment_schedule ps WHERE ps.client_account_id = NEW.client_acount_id and ps.is_active = 1); 
				
					IF @payment_schedule_id IS NOT NULL THEN
						
						SET @payment_schedule_detail_id = (SELECT psd.id FROM payment_schedule_detail psd 
																WHERE psd.payment_schedule_id = @payment_schedule_id
																AND psd.transaction_id IS NULL
																ORDER BY due_date ASC
																LIMIT 1);
						
						IF @payment_schedule_detail_id IS NOT NULL THEN
						
							UPDATE payment_schedule_detail
							SET transaction_id = NEW.id,
								amount_paid = NEW.amount,
								pending_amount = 0,
								overpayment_Amount = 0,
								status = 2,
								updated_at = NOW()
							WHERE id = @payment_schedule_detail_id;
						
						
							SET @isMonthlyCharge = (SELECT schedule_detail_id FROM charge_schedules cs WHERE cs.schedule_detail_id = @payment_schedule_detail_id LIMIT 1);
						
							IF @isMonthlyCharge IS NOT NULL THEN
								
								DELETE FROM  charge_schedules WHERE payment_schedule_id = @payment_schedule_id;
								
								CALL migration_additional_charges_payment_schedule(@payment_schedule_id, NEW.client_acount_id, _program_id, NULL);
							END IF;
						END IF;
					END IF;
				END IF; 
			END IF;
		END $$

DELIMITER ;



-- Archivo: process_recalculate_on_update_payment_schedule_onchange_ce.sql
DELIMITER $$

CREATE TRIGGER `process_recalculate_on_update_payment_schedule_onchange_ce` AFTER UPDATE ON `recurring_billings` FOR EACH ROW BEGIN 
        	DECLARE client_account_id CHAR(36);
            DECLARE payment_schedule_id BIGINT;
           	DECLARE _program_id INT;
           
            IF NEW.monthly_amount > 0 AND NEW.monthly_amount <> OLD.monthly_amount AND OLD.status <> 'CANCELED' THEN 
                SET client_account_id = OLD.client_acount_id;
               	SELECT ca.program_id INTO _program_id  from client_accounts ca where ca.id = client_account_id;
                
               	IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
	                 SELECT MAX(ps.id) INTO payment_schedule_id from payment_schedule ps
	                 WHERE ps.client_account_id = client_account_id
	                 AND ps.is_active = 1;
	                 
	                 IF payment_schedule_id IS NOT NULL THEN
	                     CALL recalculate_payment_schedule_by_clients_ce(client_account_id, 3, payment_schedule_id, _program_id, NULL);
	                 END IF;
	                 
	                 IF payment_schedule_id IS NULL THEN
	                 	CALL generate_payment_schedule_for_new_or_existing_clients(client_account_id, _program_id, 2);
					 END IF;
				END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: process_recalculate_payment_schedule_onchange_ce.sql
DELIMITER $$

CREATE TRIGGER `process_recalculate_payment_schedule_onchange_ce` AFTER INSERT ON `recurring_billings` FOR EACH ROW BEGIN 
        DECLARE client_account_id CHAR(36);
            DECLARE payment_schedule_id BIGINT;
           	DECLARE _program_id INT;

            IF NEW.monthly_amount > 0 AND NEW.updated_at IS NULL AND NEW.status <> 'CANCELED' THEN 
                SET client_account_id = NEW.client_acount_id;
                SELECT ca.program_id INTO _program_id  from client_accounts ca where ca.id = client_account_id;
                
                IF FIND_IN_SET(_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
	                SELECT MAX(ps.id) INTO payment_schedule_id from payment_schedule ps
	                WHERE ps.client_account_id = client_account_id
	                AND ps.is_active = 1;
	                
	                IF payment_schedule_id IS NOT NULL THEN
	                    CALL recalculate_payment_schedule_by_clients_ce(client_account_id, 3, payment_schedule_id, _program_id, NULL);
	                END IF;
	                
	                IF payment_schedule_id IS NULL THEN
	                    CALL generate_payment_schedule_for_new_or_existing_clients(client_account_id, _program_id, 2);
	                END IF;
                END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: recalculate_payment_schedule_ds_list_credits_insert.sql
DELIMITER $$

CREATE TRIGGER `recalculate_payment_schedule_ds_list_credits_insert` AFTER INSERT ON `ds_list_credits` FOR EACH ROW BEGIN 
            DECLARE _client_account_id CHAR(36) DEFAULT NULL;
            DECLARE _payment_schedule_id BIGINT;
            SET @debsolution_program_id = 4;
            
            IF FIND_IN_SET(@debsolution_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
                SELECT ca.id INTO _client_account_id FROM sales s 
                JOIN client_accounts ca ON ca.client_id = s.client_id
                WHERE s.event_id = NEW.event_id AND s.program_id = @debsolution_program_id AND ca.program_id = @debsolution_program_id;
               
                   SET _payment_schedule_id = (SELECT MAX(ps.id) FROM payment_schedule ps WHERE ps.client_account_id = _client_account_id AND ps.is_active = 1);
               
                   IF  NEW.ds_credit_id IS NOT NULL AND NEW.event_id IS NOT NULL AND _payment_schedule_id IS NOT NULL THEN 
                       CALL recalculate_payment_schedule_by_clients_ce(_client_account_id, 4, _payment_schedule_id, @debsolution_program_id, 12);
                   END IF;
             END IF;
        END $$

DELIMITER ;



-- Archivo: recalculate_payment_schedule_ds_list_credits_update.sql
DELIMITER $$

CREATE TRIGGER `recalculate_payment_schedule_ds_list_credits_update` AFTER UPDATE ON `ds_list_credits` FOR EACH ROW BEGIN 
            DECLARE _client_account_id CHAR(36) DEFAULT NULL;
            DECLARE _payment_schedule_id BIGINT;
            SET @debsolution_program_id = 4;
            
            IF FIND_IN_SET(@debsolution_program_id, programs_with_new_schedule(date(now()))) > 0 THEN
                SELECT ca.id INTO _client_account_id FROM sales s 
                JOIN client_accounts ca ON ca.client_id = s.client_id
                WHERE s.event_id = NEW.event_id AND s.program_id = @debsolution_program_id AND ca.program_id = @debsolution_program_id;
               
                   SET _payment_schedule_id = (SELECT MAX(ps.id) FROM payment_schedule ps WHERE ps.client_account_id = _client_account_id AND ps.is_active = 1);
               
                   
                   IF  OLD.ds_credit_id IS NULL AND NEW.ds_credit_id IS NOT NULL AND NEW.event_id IS NOT NULL AND _payment_schedule_id IS NOT NULL AND NEW.deleted_at IS NULL AND NEW.deleted_by IS NULL THEN 
                       CALL recalculate_payment_schedule_by_clients_ce(_client_account_id, 4, _payment_schedule_id, @debsolution_program_id, 12);
                   END IF;
               
               
               IF  OLD.ds_credit_id IS NOT NULL AND OLD.event_id IS NOT NULL AND _payment_schedule_id IS NOT NULL AND NEW.deleted_at IS NOT NULL AND NEW.deleted_by IS NOT NULL THEN
                       CALL recalculate_payment_schedule_by_clients_ce(_client_account_id, 4, _payment_schedule_id, @debsolution_program_id, 13);
               END IF;
            END IF;
        END $$

DELIMITER ;



-- Archivo: set_inactive_checkbook.sql
DELIMITER $$

CREATE TRIGGER `set_inactive_checkbook` AFTER INSERT ON `ds_checks` FOR EACH ROW BEGIN
                DECLARE _counter_checks int;
               	DECLARE _diff_ranges int;
                DECLARE _range_to int;
               	DECLARE _range_from int;
                             
                SELECT SUM(cb.range_to - cb.range_from) INTO _diff_ranges
                  FROM ds_checkbooks cb
                     WHERE cb.type != 1 AND cb.id = NEW.ds_checkbooks_id;
                    
                 SELECT count(*) INTO _counter_checks FROM ds_checks dc WHERE ds_checkbooks_id = NEW.ds_checkbooks_id;
                
                IF _counter_checks = _diff_ranges THEN
                 
                    UPDATE ds_checkbooks cbu SET cbu.status = 2 WHERE cbu.id = NEW.ds_checkbooks_id;
                END IF;
            END $$

DELIMITER ;



-- Archivo: tg_process_partial_refund_in_payment_schedule.sql
DELIMITER $$

CREATE TRIGGER `tg_process_partial_refund_in_payment_schedule` AFTER INSERT ON `partial_refunds_tranctions` FOR EACH ROW BEGIN
	        
        	SET @type_refund_parcial := 17;
           	SET @modality_monthly := 1;
            SET @mode_recalculate := 8;
          
            SELECT ps.id, ca.id, ca.program_id  
            INTO @payment_schedule_id, @client_acount_id, @program_id
            FROM transactions t 
            JOIN payment_schedule ps on ps.client_account_id = t.client_acount_id
            JOIN client_accounts ca on ca.id = t.client_acount_id 
            where t.transaction_id =  NEW.transaction_id 
            AND ps.is_active = 1
            AND ps.id = (SELECT MAX(id) FROM payment_schedule WHERE client_account_id = t.client_acount_id  AND is_active = 1)
            AND t.status_transaction_id IN(1,5,8)
            AND t.modality_transaction_id = @modality_monthly
            AND t.type_transaction_id = @type_refund_parcial; 
			
			IF @payment_schedule_id IS NOT NULL AND FIND_IN_SET(@program_id, programs_with_new_schedule(date(now()))) > 0 THEN
				CALL recalculate_payment_schedule_by_clients_ce(@client_acount_id, 4, @payment_schedule_id, @program_id, @mode_recalculate);
			END IF;
        END $$

DELIMITER ;



-- Archivo: tg_process_partial_void_in_payment_schedule.sql
DELIMITER $$

CREATE TRIGGER `tg_process_partial_void_in_payment_schedule` AFTER UPDATE ON `pending_void_transactions` FOR EACH ROW BEGIN
                    
        	SET @type_void_parcial := 16;
            SET @modality_monthly := 1;
            SET @mode_recalculate := 7;
          
            SELECT ps.id, ca.id, ca.program_id  
            INTO @payment_schedule_id, @client_acount_id, @program_id
            FROM transactions t 
            JOIN payment_schedule ps on ps.client_account_id = t.client_acount_id
            JOIN client_accounts ca on ca.id = t.client_acount_id 
            where t.transaction_id =  NEW.transaction_id 
            AND ps.is_active = 1
            AND ps.id = (SELECT MAX(id) FROM payment_schedule WHERE client_account_id = t.client_acount_id  AND is_active = 1)
            AND t.status_transaction_id IN(1,5,8)
            AND t.modality_transaction_id = @modality_monthly
            AND t.type_transaction_id = @type_void_parcial; 
            
            IF @payment_schedule_id IS NOT NULL AND NEW.updated_at IS NOT NULL AND FIND_IN_SET(@program_id, programs_with_new_schedule(date(now()))) > 0 THEN
                CALL recalculate_payment_schedule_by_clients_ce(@client_acount_id, 4, @payment_schedule_id, @program_id, @mode_recalculate);
            END IF;
        END $$

DELIMITER ;



-- Archivo: trigger_insert_program_deployment_dates.sql
DELIMITER $$

CREATE TRIGGER `trigger_insert_program_deployment_dates` BEFORE INSERT ON `program_deployment_dates` FOR EACH ROW BEGIN
            DECLARE existing_count INT;
			select exists(SELECT id  FROM program_deployment_dates WHERE program_id = NEW.program_id ) INTO existing_count;
			  
		    IF existing_count = 1 THEN  
		      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un registro con el mismo program_id y date.';
            ELSE
		      set NEW.deployment_date = DATE_FORMAT(NEW.deployment_date,'%Y-%m-%01');
		    END IF; 
        END $$

DELIMITER ;



-- Archivo: trigger_update_program_deployment_dates.sql
DELIMITER $$

CREATE TRIGGER `trigger_update_program_deployment_dates` BEFORE UPDATE ON `program_deployment_dates` FOR EACH ROW BEGIN 
		    
        END $$

DELIMITER ;



-- Archivo: update_ced_role_value_commission.sql
DELIMITER $$

CREATE TRIGGER `update_ced_role_value_commission` AFTER UPDATE ON `ced_settings_commission_roles_tracking` FOR EACH ROW BEGIN 
            IF (NEW.status = 2) THEN
            
            UPDATE ced_settings_commission_roles 
            SET value = NEW.new_value
            WHERE id = NEW.ced_setting_commission_role_id;
        
            END IF;
        END $$

DELIMITER ;



-- Archivo: update_ced_type_value_commission.sql
DELIMITER $$

CREATE TRIGGER `update_ced_type_value_commission` AFTER UPDATE ON `ced_setting_commission_tracking` FOR EACH ROW BEGIN 
            IF (NEW.status = 2) THEN
            
            UPDATE ced_setting_commission_type 
            SET value = NEW.new_value
            WHERE id = NEW.ced_setting_commission_type_id;
        
            END IF;
        END $$

DELIMITER ;



-- Archivo: update_last_event_tracking.sql
DELIMITER $$

CREATE TRIGGER `update_last_event_tracking` AFTER INSERT ON `sales` FOR EACH ROW BEGIN
            IF NEW.event_id IS NOT NULL THEN
               UPDATE event_tracking et
				JOIN (
				    SELECT MAX(id) as id, event_id
				    FROM event_tracking
				    GROUP BY event_id
				) x ON x.id = et.id
				SET et.sale_id = NEW.id
				where et.event_id = NEW.event_id;
            END IF;
        END $$

DELIMITER ;



-- Archivo: update_services_quantity_by_client.sql
DELIMITER $$

CREATE TRIGGER `update_services_quantity_by_client` AFTER INSERT ON `client_accounts` FOR EACH ROW BEGIN
                update clients c set qty_services = (
                    select count(ca.id) from client_accounts ca
                    where ca.client_id = c.id
                ) where c.id = NEW.client_id;
            END $$

DELIMITER ;



-- Archivo: update_total_debt_for_client_on_ds_list_credit_insert.sql
DELIMITER $$

CREATE TRIGGER `update_total_debt_for_client_on_ds_list_credit_insert` AFTER INSERT ON `ds_list_credits` FOR EACH ROW BEGIN
                CALL update_total_client_ds_debt(NEW.event_id);
        END $$

DELIMITER ;



-- Archivo: update_total_debt_for_client_on_ds_list_credit_update.sql
DELIMITER $$

CREATE TRIGGER `update_total_debt_for_client_on_ds_list_credit_update` AFTER UPDATE ON `ds_list_credits` FOR EACH ROW BEGIN
                if (NEW.actual_balance <> OLD.actual_balance) THEN
                    CALL update_total_client_ds_debt(NEW.event_id);
                END IF;
        END $$

DELIMITER ;



