USE master;
GO

IF DB_ID(N'Com3900G02') IS NOT NULL
BEGIN
    -- Corta TODAS las conexiones a la base y hace rollback de lo que estén haciendo y elimina la bdd
    ALTER DATABASE Com3900G02 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Com3900G02;
END
GO

-- creamos la base de datos 
CREATE DATABASE Com3900G02;
GO

USE Com3900G02;

--creamos el esquema 
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dbo')
    EXEC(N'CREATE SCHEMA dbo');
GO


--creacion de tablas
CREATE TABLE dbo.Consorcio (
    id              INT IDENTITY(1,1) NOT NULL,
    nombre          VARCHAR(100)    NOT NULL,
    domicilio       VARCHAR(100)    NOT NULL,
    cantidadUnidades INT             NOT NULL,
    m2totales       INT NOT NULL CHECK ( m2totales >= 0 ),
    CONSTRAINT PK_Consorcio PRIMARY KEY (id)
);
GO

CREATE TABLE dbo.persona (
    id        INT IDENTITY(1,1) NOT NULL,
    nombre    VARCHAR(100),
    apellido  VARCHAR(100),
    dni       INT,
    email     VARCHAR(100),
    telefono  VARCHAR(20),
    cbu_cvu   VARCHAR(30)       NULL CHECK (cbu_cvu NOT LIKE '%[^0-9]%'),
    tipoTitularidad varchar(11),
    CONSTRAINT PK_Persona PRIMARY KEY (id),
    CONSTRAINT UQ_Persona_dni UNIQUE (dni)  -- unicidad para la importacion de datos
);
GO

CREATE TABLE dbo.PrestadorServicio (
    id           INT IDENTITY(1,1) NOT NULL,
    idConsorcio INT NOT NULL,
    nombre       VARCHAR(100)      NOT NULL,
    tipoServicio VARCHAR(100)      NULL,
    cuenta       VARCHAR(100)       NULL CHECK (cuenta NOT LIKE '%[^0-9]%'),
    CONSTRAINT PK_PrestadorServicio PRIMARY KEY (id),
    CONSTRAINT FK_PrestadorServicio_Consorcio FOREIGN KEY (idConsorcio)
        REFERENCES dbo.Consorcio (id)
);
GO

-- Hay que tener en cuenta que el numeroUnidad se repite por lo que vamos a tener
-- varios para cada UF, puede ser PRIMARY KEY (numeroUnidad,idConsorcio),
-- o hay que hacer una key diferente para que no sea entidad debil 

CREATE TABLE dbo.UnidadFuncional (
    idUF            INT IDENTITY(1,1) NOT NULL,
    idConsorcio     INT          NOT NULL,
    numeroUnidad    INT          NOT NULL,
    piso            SMALLINT     NULL,
    departamento    VARCHAR(10)  NULL,
    coeficiente     DECIMAL(3,1) NOT NULL,
    m2_UF           INT          NOT NULL,
    cbu_cvu_actual  VARCHAR(30)  NULL CHECK (cbu_cvu_actual NOT LIKE '%[^0-9]%'),
    CONSTRAINT PK_UnidadFuncional           PRIMARY KEY (idUF),
    CONSTRAINT UQ_UF_Consorcio_Num          UNIQUE (idConsorcio, numeroUnidad),
    CONSTRAINT FK_UnidadFuncional_Consorcio FOREIGN KEY (idConsorcio) REFERENCES dbo.Consorcio(id),
    CONSTRAINT CK_UF_m2_pos                 CHECK (m2_UF > 0),
    CONSTRAINT CK_UF_coeficiente            CHECK (coeficiente >= 0)
);
GO

CREATE TABLE dbo.UnidadAccesoria (
    id                INT IDENTITY(1,1) NOT NULL,
    idUnidadFuncional INT             NOT NULL,
    cochera bit default 0,
    baulera bit default 0,
    m2_baulera           INT         NOT NULL CHECK (m2_baulera >= 0),
    m2_cochera           INT         NOT NULL CHECK (m2_cochera >= 0),
    CONSTRAINT PK_UnidadAccesoria PRIMARY KEY (id),
    CONSTRAINT FK_UnidadAccesoria_UF         FOREIGN KEY (idUnidadFuncional)        REFERENCES dbo.UnidadFuncional (idUF)
);
GO

CREATE TABLE dbo.Pago (
    id                 INT IDENTITY(1,1) NOT NULL,
    nroUnidadFuncional INT             NULL,
    fechaPago          DATE            NOT NULL,
    cbu                VARCHAR(30)    NOT NULL,
    monto              DECIMAL(10,2)   NOT NULL,
    idDePago           INT NOT NULL,
    CONSTRAINT PK_Pago PRIMARY KEY (id),
    CONSTRAINT UQ_Pago_idDePago UNIQUE (idDePago),
    CONSTRAINT FK_Pago_UnidadFuncional FOREIGN KEY (nroUnidadFuncional) REFERENCES dbo.UnidadFuncional (idUF)
);
GO


CREATE TABLE dbo.Expensa (
    id                 INT IDENTITY(1,1) NOT NULL,
    idUF               INT             NOT NULL,
    periodo            DATE           NOT NULL,
    montoTotal         DECIMAL(10,2)   NOT NULL CHECK(montoTotal>0),
    fechaEnvio         DATE            NULL,
    modoEnvio          VARCHAR(50)    NULL,
    CONSTRAINT PK_Expensa PRIMARY KEY (id),
    CONSTRAINT FK_Expensa_UF   FOREIGN KEY (idUF)   REFERENCES dbo.UnidadFuncional (idUF),
    CONSTRAINT UQ_Expensa_UF_Periodo UNIQUE (idUF, periodo)     -- 1 expensa por UF/mes
);
GO

CREATE TABLE dbo.DetalleExpensa (
    id                  INT IDENTITY(1,1) NOT NULL,
    idExpensa           INT             NOT NULL,
    idPrestadorServicio INT             NOT NULL,
    importe             DECIMAL(10,2)   NOT NULL,
    nroFactura          VARCHAR(50)    NULL,
    tipo                VARCHAR(50)    NULL,
    categoria           VARCHAR(50)    NULL,
    CONSTRAINT PK_DetalleExpensa    PRIMARY KEY (id),
    CONSTRAINT FK_DetalleExpensa_Expensa    FOREIGN KEY (idExpensa)    REFERENCES dbo.Expensa (id),
    CONSTRAINT FK_DetalleExpensa_PrestadorServicio  FOREIGN KEY (idPrestadorServicio)    REFERENCES dbo.PrestadorServicio (id)
);
GO

CREATE TABLE dbo.FacturaExpensa (
    numeroFactura        INT IDENTITY(1,1) NOT NULL,
    idExpensa            INT             NOT NULL,
    fechaEmision         DATE            NOT NULL,
    fechaVencimiento     DATE            NOT NULL,
    nroVencimiento       INT             NOT NULL CHECK (nroVencimiento > 0),
    interesPorMora       DECIMAL(10,2)   DEFAULT 0,
    totalGastoOrdinario  DECIMAL(10,2)   DEFAULT 0,
    totalGastoExtraordinario DECIMAL(10,2) DEFAULT 0,
    CONSTRAINT PK_FacturaExpensa PRIMARY KEY (numeroFactura),
    CONSTRAINT FK_FacturaExpensa_Expensa FOREIGN KEY (idExpensa)
        REFERENCES dbo.Expensa (id)
);
GO

CREATE TABLE dbo.EstadoFinanciero (
    id             INT IDENTITY(1,1) NOT NULL,
    idExpensa      INT             NOT NULL,
    saldoAnterior  DECIMAL(10,2)   DEFAULT 0, 
    saldoNuevo     DECIMAL(10,2)   DEFAULT 0,
    saldoDeudor    DECIMAL(10,2)   DEFAULT 0,
    saldoAdelantado DECIMAL(10,2)  DEFAULT 0,
    saldoTotal     DECIMAL(10,2)   DEFAULT 0,
    CONSTRAINT PK_EstadoFinanciero PRIMARY KEY (id),
    CONSTRAINT FK_EstadoFinanciero_Expensa FOREIGN KEY (idExpensa)
        REFERENCES dbo.Expensa (id)
);
GO


CREATE TABLE dbo.Feriados (
    fecha  DATE        NOT NULL PRIMARY KEY,
    tipo   NVARCHAR(50)    NULL,
    nombre NVARCHAR(200)   NULL
);