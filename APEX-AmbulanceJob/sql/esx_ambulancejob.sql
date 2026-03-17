-- esx_ambulancejob required SQL
-- Import this file once into your ESX database.

START TRANSACTION;

-- Job definition
INSERT IGNORE INTO `jobs` (`name`, `label`) VALUES
  ('ambulance', 'EMS');

-- Job grades
INSERT IGNORE INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
  ('ambulance', 0, 'trainee',    'Trainee',    300, '{}', '{}'),
  ('ambulance', 1, 'paramedic',  'Paramedic',  450, '{}', '{}'),
  ('ambulance', 2, 'doctor',     'Doctor',     600, '{}', '{}'),
  ('ambulance', 3, 'surgeon',    'Surgeon',    800, '{}', '{}'),
  ('ambulance', 4, 'boss',       'Chief',     1000, '{}', '{}');

-- Society account / datastore / inventory used by ambulance billing & management flows
INSERT IGNORE INTO `addon_account` (`name`, `label`, `shared`) VALUES
  ('society_ambulance', 'Ambulance', 1);

INSERT IGNORE INTO `datastore` (`name`, `label`, `shared`) VALUES
  ('society_ambulance', 'Ambulance', 1);

INSERT IGNORE INTO `addon_inventory` (`name`, `label`, `shared`) VALUES
  ('society_ambulance', 'Ambulance', 1);

COMMIT;
