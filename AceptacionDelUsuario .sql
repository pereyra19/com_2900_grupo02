USE Com3900G02;
GO

/* 1. Consorcios con BAULERA y COCHERA */
SELECT 
    c.id,
    c.nombre,
    COUNT(DISTINCT uf.idUF) AS cantUF,
    SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END) AS ufs_con_baulera,
    SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END) AS ufs_con_cochera
FROM dbo.Consorcio c
JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = c.id
LEFT JOIN dbo.UnidadAccesoria ua ON ua.idUnidadFuncional = uf.idUF
GROUP BY c.id, c.nombre
HAVING 
    COALESCE(SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END),0) > 0
AND COALESCE(SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END),0) > 0;
GO

/* 2. Consorcios SIN BAULERA y SIN COCHERA */
SELECT 
    c.id,
    c.nombre,
    COUNT(DISTINCT uf.idUF) AS cantUF,
    SUM(CASE WHEN ua.baulera = 1 OR ua.cochera = 1 THEN 1 ELSE 0 END) AS ufs_con_accesorios
FROM dbo.Consorcio c
JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = c.id
LEFT JOIN dbo.UnidadAccesoria ua ON ua.idUnidadFuncional = uf.idUF
GROUP BY c.id, c.nombre
HAVING 
    COALESCE(SUM(CASE WHEN ua.baulera = 1 OR ua.cochera = 1 THEN 1 ELSE 0 END),0) = 0;
GO

/* 3. Consorcios con BAULERA SOLAMENTE */
SELECT 
    c.id,
    c.nombre,
    COUNT(DISTINCT uf.idUF) AS cantUF,
    SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END) AS ufs_con_baulera,
    SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END) AS ufs_con_cochera
FROM dbo.Consorcio c
JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = c.id
LEFT JOIN dbo.UnidadAccesoria ua ON ua.idUnidadFuncional = uf.idUF
GROUP BY c.id, c.nombre
HAVING 
    COALESCE(SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END),0) > 0
AND COALESCE(SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END),0) = 0;
GO

/* 4. Consorcios con COCHERA SOLAMENTE */
SELECT 
    c.id,
    c.nombre,
    COUNT(DISTINCT uf.idUF) AS cantUF,
    SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END) AS ufs_con_baulera,
    SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END) AS ufs_con_cochera
FROM dbo.Consorcio c
JOIN dbo.UnidadFuncional uf ON uf.idConsorcio = c.id
LEFT JOIN dbo.UnidadAccesoria ua ON ua.idUnidadFuncional = uf.idUF
GROUP BY c.id, c.nombre
HAVING 
    COALESCE(SUM(CASE WHEN ua.cochera = 1 THEN 1 ELSE 0 END),0) > 0
AND COALESCE(SUM(CASE WHEN ua.baulera = 1 THEN 1 ELSE 0 END),0) = 0;
GO
