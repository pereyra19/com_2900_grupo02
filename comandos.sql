CREATE DATABASE tato;

USE tato;

CREATE TABLE cuatrimestre
(
	id int primary key, 
	numero int,
	cantMateria int, 
);

CREATE TABLE materias
(
    nombre VARCHAR(20) PRIMARY KEY,
    examen DATE,
    nota DECIMAL(4,2),
    cuatrimestre_id INT,   -- <--- aquí la relación
    FOREIGN KEY (cuatrimestre_id) REFERENCES cuatrimestre(id)
);

INSERT INTO cuatrimestre (id, numero, cantMateria) VALUES
(1, 1, 5),
(2, 2, 4),
(3, 3, 6);

INSERT INTO materias (nombre, examen, nota, cuatrimestre_id) VALUES
('Matematicas', '2025-12-15', 8.5, 1),
('Fisica', '2025-12-20', 7.0, 1),
('Quimica', '2025-12-22', 9.0, 1),
('Historia', '2025-12-18', 6.5, 2),
('Literatura', '2025-12-19', 8.0, 2),
('Biologia', '2025-12-21', 7.5, 3),
('Ingles', '2025-12-23', 9.0, 3);

drop table ventas;

CREATE TABLE VENTAS
(
   id int identity(1,1) primary key,
   cantidad int,
   precio decimal(3,2),
   fechaOrden date,
   Vendedor varchar(100),
);

--cambiar tipo de dato
ALTER TABLE ventas
ALTER COLUMN precio NUMERIC(10,2) NOT NULL;

insert into ventas(cantidad,precio,fechaOrden,Vendedor) values
  (1,  840.00, '2019-01-22 21:25:00', 'Web'),
  (1,   17.94, '2019-01-28 14:15:00', 'Florencia'),
  (2,   14.39, '2019-01-17 13:33:00', 'Jasmine'),
  (1,  179.99, '2019-01-05 20:33:00', 'Web'),
  (1,   14.39, '2019-01-25 11:59:00', 'Jasmine'); 

select * from ventas;

WITH cte as(
    SELECT 
        vendedor,
        MONTH(fechaOrden) as mes,
        cantidad * precio as monto
        from VENTAS
)
select * from cte 
-- ISNULL([1],0) ISNULL([2],0) para eliminar los 0
pivot ( 
    sum(monto) for mes in ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
) pvt
ORDER BY Vendedor;



        
   

















