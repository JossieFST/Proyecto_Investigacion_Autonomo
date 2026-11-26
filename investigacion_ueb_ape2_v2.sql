-- phpMyAdmin SQL Dump
-- version 5.2.4-dev+20260809.e0909b211bdeb1
-- https://www.phpmyadmin.net/
--
-- Servidor: localhost:3306
-- Tiempo de generación: 26-11-2026 a las 22:04:09
-- Versión del servidor: 11.8.9-MariaDB-2 from PikaOS
-- Versión de PHP: 8.4.26

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `investigacion_ueb_ape2_v2`
--
CREATE DATABASE IF NOT EXISTS `investigacion_ueb_ape2_v2` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `investigacion_ueb_ape2_v2`;

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_docentes_dos_proyectos_activos` ()   BEGIN
  SELECT pa.Cod_Profesor, prf.Nombres_Apellidos,
         COUNT(DISTINCT pa.AIP) AS Proyectos_Activos
  FROM Participa pa
  JOIN Proyecto_de_Investigacion pr ON pr.AIP=pa.AIP
  JOIN Profesor prf ON prf.Cod_Profesor=pa.Cod_Profesor
  WHERE pa.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
    AND pr.Estado_Proyecto='ACTIVO'
    AND pa.Fecha_Inicio<=CURRENT_DATE()
    AND (pa.Fecha_Fin IS NULL OR pa.Fecha_Fin>=CURRENT_DATE())
  GROUP BY pa.Cod_Profesor, prf.Nombres_Apellidos
  HAVING COUNT(DISTINCT pa.AIP)>=2
  ORDER BY Proyectos_Activos DESC, prf.Nombres_Apellidos;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_equipo_proyecto` (IN `p_AIP` VARCHAR(20))   BEGIN
  SELECT p.AIP, pa.Rol, pa.Cod_Profesor,
         pr.Nombres_Apellidos, pa.Fecha_Inicio, pa.Fecha_Fin
  FROM Participa pa
  JOIN Profesor pr ON pr.Cod_Profesor=pa.Cod_Profesor
  JOIN Proyecto_de_Investigacion p ON p.AIP=pa.AIP
  WHERE pa.AIP=p_AIP
  ORDER BY FIELD(pa.Rol,'DIRECTOR','SUBROGANTE','INVESTIGADOR'),
           pa.Fecha_Inicio, pr.Nombres_Apellidos;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_productos_proyecto` (IN `p_AIP` VARCHAR(20))   BEGIN
  SELECT p.AIP, p.N_Secuencia, p.Titulo, p.Tipo_Publicacion,
         CASE
           WHEN r.AIP IS NOT NULL THEN CONCAT('Revista: ',r.Nombre_Revista,' / ',r.Clase)
           WHEN c.AIP IS NOT NULL THEN CONCAT('Congreso: ',c.Nombre_Congreso,' / ',c.Tipo_Congreso)
           WHEN l.AIP IS NOT NULL THEN CONCAT('Libro ISBN: ',l.ISBN)
           WHEN pa.AIP IS NOT NULL THEN CONCAT('Patente: ',pa.N_Registro,' / ',pa.Estado)
           ELSE 'Sin detalle de especialización'
         END AS Detalle
  FROM Productos p
  LEFT JOIN Publicacion_Revista r ON r.AIP=p.AIP AND r.N_Secuencia=p.N_Secuencia
  LEFT JOIN Publicacion_Congreso c ON c.AIP=p.AIP AND c.N_Secuencia=p.N_Secuencia
  LEFT JOIN Libros l ON l.AIP=p.AIP AND l.N_Secuencia=p.N_Secuencia
  LEFT JOIN Patentes pa ON pa.AIP=p.AIP AND pa.N_Secuencia=p.N_Secuencia
  WHERE p.AIP=p_AIP
  ORDER BY p.N_Secuencia;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_proyectos_por_estado` (IN `p_estado` VARCHAR(15))   BEGIN
  SELECT AIP, Nombre, Acronimo, Fecha_Inicio, Fecha_Fin,
         Estado_Proyecto, Tiene_Prorroga
  FROM Proyecto_de_Investigacion
  WHERE p_estado IS NULL OR Estado_Proyecto=p_estado
  ORDER BY Fecha_Inicio DESC;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_proyectos_sin_productos` ()   BEGIN
  SELECT pr.AIP, pr.Nombre, pr.Estado_Proyecto, pr.Fecha_Inicio, pr.Fecha_Fin
  FROM Proyecto_de_Investigacion pr
  WHERE NOT EXISTS (
    SELECT 1 FROM Productos p WHERE p.AIP=pr.AIP
  )
  ORDER BY pr.Fecha_Inicio DESC;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_tx_aprobar_prorroga` (IN `p_Cod_Prorroga` VARCHAR(12), IN `p_Resolucion` VARCHAR(250), IN `p_Fecha_Resolucion` DATE)   BEGIN
    DECLARE v_aip         VARCHAR(20);
    DECLARE v_meses       TINYINT UNSIGNED;
    DECLARE v_estado_sol  VARCHAR(12);
    DECLARE v_fin_actual  DATE;
    DECLARE v_inicio_pror DATE;
    DECLARE v_fin_pror    DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
        VALUES ('APROBAR_PRORROGA', 'sp_tx_aprobar_prorroga', 'ERROR', CONCAT('Fallo aprobando prórroga ', p_Cod_Prorroga));
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT AIP, Duracion_Meses, Estado_Solicitud
      INTO v_aip, v_meses, v_estado_sol
      FROM Prorroga
     WHERE Cod_Prorroga = TRIM(p_Cod_Prorroga)
     FOR UPDATE;

    IF v_aip IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud de prórroga especificada no existe.';
    END IF;

    IF v_estado_sol <> 'PENDIENTE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden aprobar prórrogas en estado PENDIENTE.';
    END IF;

    SELECT Fecha_Fin INTO v_fin_actual FROM Proyecto_de_Investigacion WHERE AIP = v_aip FOR UPDATE;

    SET v_inicio_pror = DATE_ADD(v_fin_actual, INTERVAL 1 DAY);
    SET v_fin_pror    = DATE_ADD(v_fin_actual, INTERVAL v_meses MONTH);

    UPDATE Prorroga
       SET Estado_Solicitud = 'APROBADA',
           Fecha_Inicio     = v_inicio_pror,
           Fecha_Fin        = v_fin_pror,
           Resolucion       = TRIM(p_Resolucion),
           Fecha_Resolucion = COALESCE(p_Fecha_Resolucion, CURRENT_DATE())
     WHERE Cod_Prorroga = TRIM(p_Cod_Prorroga);

    UPDATE Proyecto_de_Investigacion
       SET Fecha_Fin = v_fin_pror, Tiene_Prorroga = 'SI'
     WHERE AIP = v_aip;

    INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
    VALUES ('APROBAR_PRORROGA', 'sp_tx_aprobar_prorroga', 'EXITOSA', CONCAT('Prórroga ', p_Cod_Prorroga, ' aprobada para ', v_aip));

    COMMIT;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_tx_asignar_investigador` (IN `p_Cod_Profesor` VARCHAR(12), IN `p_AIP` VARCHAR(20), IN `p_Fecha_Inicio` DATE, IN `p_Rol` VARCHAR(15))   BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
        VALUES ('ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', CONCAT('Fallo asignando ', p_Cod_Profesor, ' a ', p_AIP));
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO Participa (Cod_Profesor, Cod_Estudiante, AIP, Fecha_Inicio, Fecha_Fin, Rol)
    VALUES (
        TRIM(p_Cod_Profesor),
        NULL,
        TRIM(p_AIP),
        COALESCE(p_Fecha_Inicio, CURRENT_DATE()),
        NULL,
        UPPER(TRIM(p_Rol))
    );

    INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
    VALUES ('ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'EXITOSA', CONCAT('Asignado ', p_Cod_Profesor, ' (', p_Rol, ') en ', p_AIP));

    COMMIT;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_tx_cambiar_personal` (IN `p_AIP` VARCHAR(20), IN `p_Cod_Profesor_Sale` VARCHAR(12), IN `p_Cod_Profesor_Entra` VARCHAR(12), IN `p_Fecha_Cambio` DATE, IN `p_Rol` VARCHAR(150))   BEGIN
    DECLARE v_id_part      BIGINT;
    DECLARE v_rol_actual   VARCHAR(15);
    DECLARE v_rol_nuevo    VARCHAR(15);
    DECLARE v_inicio_sale  DATE;
    DECLARE v_fecha_cambio DATE;
    DECLARE v_fecha_cierre DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
        VALUES ('CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', CONCAT('Fallo relevo en ', p_AIP, ': ', p_Cod_Profesor_Sale, ' -> ', p_Cod_Profesor_Entra));
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_fecha_cambio = COALESCE(p_Fecha_Cambio, CURRENT_DATE());

    SELECT Id_Participacion, Rol, Fecha_Inicio
      INTO v_id_part, v_rol_actual, v_inicio_sale
      FROM Participa
     WHERE AIP = TRIM(p_AIP)
       AND Cod_Profesor = TRIM(p_Cod_Profesor_Sale)
       AND (Fecha_Fin IS NULL OR Fecha_Fin >= v_fecha_cambio)
     ORDER BY Fecha_Inicio DESC
     LIMIT 1;

    IF v_id_part IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El docente saliente no tiene una participación vigente en el proyecto.';
    END IF;

    IF UPPER(TRIM(COALESCE(p_Rol, ''))) IN ('DIRECTOR', 'SUBROGANTE', 'INVESTIGADOR') THEN
        SET v_rol_nuevo = UPPER(TRIM(p_Rol));
    ELSE
        SET v_rol_nuevo = v_rol_actual;
    END IF;

    IF v_fecha_cambio > v_inicio_sale THEN
        SET v_fecha_cierre = DATE_SUB(v_fecha_cambio, INTERVAL 1 DAY);
    ELSE
        SET v_fecha_cierre = v_fecha_cambio;
    END IF;

    UPDATE Participa
       SET Fecha_Fin = v_fecha_cierre
     WHERE Id_Participacion = v_id_part;

    INSERT INTO Participa (Cod_Profesor, Cod_Estudiante, AIP, Fecha_Inicio, Fecha_Fin, Rol)
    VALUES (
        TRIM(p_Cod_Profesor_Entra),
        NULL,
        TRIM(p_AIP),
        v_fecha_cambio,
        NULL,
        v_rol_nuevo
    );

    INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
    VALUES ('CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'EXITOSA', CONCAT('Relevo en ', p_AIP, ': ', p_Cod_Profesor_Sale, ' -> ', p_Cod_Profesor_Entra));

    COMMIT;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_tx_registrar_producto` (IN `p_AIP` VARCHAR(20), IN `p_N_Secuencia` INT, IN `p_Titulo` VARCHAR(250), IN `p_Tipo` VARCHAR(12), IN `p_Detalle_JSON` LONGTEXT, IN `p_Autores_JSON` LONGTEXT)   BEGIN
    DECLARE v_sec  INT;
    DECLARE v_tipo VARCHAR(12);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
        VALUES ('REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'ERROR', CONCAT('Fallo al registrar producto en ', p_AIP));
        RESIGNAL;
    END;

    START TRANSACTION;

    SET v_tipo = UPPER(TRIM(p_Tipo));

    IF p_N_Secuencia IS NULL OR p_N_Secuencia <= 0 THEN
        SELECT COALESCE(MAX(N_Secuencia), 0) + 1 INTO v_sec FROM Productos WHERE AIP = TRIM(p_AIP);
    ELSE
        SET v_sec = p_N_Secuencia;
    END IF;

    INSERT INTO Productos (AIP, N_Secuencia, Titulo, Tipo_Publicacion)
    VALUES (TRIM(p_AIP), v_sec, TRIM(p_Titulo), v_tipo);

    IF v_tipo = 'REVISTA' THEN
        INSERT INTO Publicacion_Revista (
            AIP, N_Secuencia, Nombre_Revista, Editorial,
            Pagina_Inicio, Pagina_Fin, Volumen, Numero_Revista, Clase, Categoria_Revista
        ) VALUES (
            TRIM(p_AIP), v_sec,
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Nombre_Revista'), JSON_EXTRACT(p_Detalle_JSON, '$.nombreRevista'))),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Editorial'), JSON_EXTRACT(p_Detalle_JSON, '$.editorial'))),
            CAST(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Pagina_Inicio'), JSON_EXTRACT(p_Detalle_JSON, '$.paginaInicio'))) AS UNSIGNED),
            CAST(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Pagina_Fin'), JSON_EXTRACT(p_Detalle_JSON, '$.paginaFin'))) AS UNSIGNED),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Volumen'), JSON_EXTRACT(p_Detalle_JSON, '$.volumen'))),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Numero_Revista'), JSON_EXTRACT(p_Detalle_JSON, '$.numeroRevista'))),
            UPPER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Clase'), JSON_EXTRACT(p_Detalle_JSON, '$.clase')))),
            COALESCE(NULLIF(UPPER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Categoria_Revista'), JSON_EXTRACT(p_Detalle_JSON, '$.categoriaRevista')))), ''), 'ALTO_IMPACTO')
        );
    ELSEIF v_tipo = 'CONGRESO' THEN
        INSERT INTO Publicacion_Congreso (
            AIP, N_Secuencia, Nombre_Congreso, Tipo_Congreso,
            Lugar, Pais, Editorial, Fecha_Inicio, Fecha_Final
        ) VALUES (
            TRIM(p_AIP), v_sec,
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Nombre_Congreso'), JSON_EXTRACT(p_Detalle_JSON, '$.nombreCongreso'))),
            UPPER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Tipo_Congreso'), JSON_EXTRACT(p_Detalle_JSON, '$.tipoCongreso')))),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Lugar'), JSON_EXTRACT(p_Detalle_JSON, '$.lugar'))),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Pais'), JSON_EXTRACT(p_Detalle_JSON, '$.pais'))),
            NULLIF(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Editorial'), JSON_EXTRACT(p_Detalle_JSON, '$.editorial'))), 'null'),
            STR_TO_DATE(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Fecha_Inicio'), JSON_EXTRACT(p_Detalle_JSON, '$.fechaInicio'))), '%Y-%m-%d'),
            STR_TO_DATE(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Fecha_Final'), JSON_EXTRACT(p_Detalle_JSON, '$.fechaFinal'))), '%Y-%m-%d')
        );
    ELSEIF v_tipo = 'LIBRO' THEN
        INSERT INTO Libros (AIP, N_Secuencia, ISBN, Editorial, Anio_Publicacion)
        VALUES (
            TRIM(p_AIP), v_sec,
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.ISBN'), JSON_EXTRACT(p_Detalle_JSON, '$.isbn'))),
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Editorial'), JSON_EXTRACT(p_Detalle_JSON, '$.editorial'))),
            CAST(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Anio_Publicacion'), JSON_EXTRACT(p_Detalle_JSON, '$.anioPublicacion'))) AS SIGNED)
        );
    ELSEIF v_tipo = 'PATENTE' THEN
        INSERT INTO Patentes (AIP, N_Secuencia, N_Registro, Fecha_Registro, Estado)
        VALUES (
            TRIM(p_AIP), v_sec,
            JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.N_Registro'), JSON_EXTRACT(p_Detalle_JSON, '$.nRegistro'))),
            STR_TO_DATE(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Fecha_Registro'), JSON_EXTRACT(p_Detalle_JSON, '$.fechaRegistro'))), '%Y-%m-%d'),
            UPPER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(p_Detalle_JSON, '$.Estado'), JSON_EXTRACT(p_Detalle_JSON, '$.estado'))))
        );
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tipo de publicación no válido (use REVISTA, CONGRESO, LIBRO o PATENTE).';
    END IF;

    IF p_Autores_JSON IS NOT NULL AND JSON_LENGTH(p_Autores_JSON) > 0 THEN
        INSERT INTO Escribe (Cod_Profesor, AIP, N_Secuencia, Cod_Linea)
        SELECT
            TRIM(COALESCE(jt.prof1, jt.prof2)),
            TRIM(p_AIP),
            v_sec,
            TRIM(COALESCE(jt.lin1, jt.lin2))
        FROM JSON_TABLE(
            p_Autores_JSON,
            '$[*]' COLUMNS (
                prof1 VARCHAR(12) PATH '$.Cod_Profesor',
                prof2 VARCHAR(12) PATH '$.codProfesor',
                lin1  VARCHAR(12) PATH '$.Cod_Linea',
                lin2  VARCHAR(12) PATH '$.codLinea'
            )
        ) AS jt;
    END IF;

    INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
    VALUES ('REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'EXITOSA', CONCAT('Producto #', v_sec, ' registrado en ', p_AIP));

    COMMIT;
END$$

CREATE DEFINER=`yosij`@`localhost` PROCEDURE `sp_tx_registrar_proyecto` (IN `p_AIP` VARCHAR(20), IN `p_Nombre` VARCHAR(200), IN `p_Acronimo` VARCHAR(35), IN `p_Cod_Programa` VARCHAR(12), IN `p_Cod_Finanza` VARCHAR(12), IN `p_Fecha_Inicio` DATE, IN `p_Fecha_Fin` DATE, IN `p_Descripcion` TEXT, IN `p_Participantes_JSON` LONGTEXT, IN `p_Lineas_JSON` LONGTEXT)   BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
        VALUES ('REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', CONCAT('Fallo al registrar proyecto ', p_AIP));
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO Proyecto_de_Investigacion (
        AIP, Nombre, Acronimo, Cod_Programa, Cod_Finanza,
        Fecha_Inicio, Fecha_Fin, Descripcion_Objetivos, Estado_Proyecto, Tiene_Prorroga
    ) VALUES (
        TRIM(p_AIP), TRIM(p_Nombre), TRIM(p_Acronimo),
        NULLIF(TRIM(p_Cod_Programa), ''), NULLIF(TRIM(p_Cod_Finanza), ''),
        p_Fecha_Inicio, p_Fecha_Fin, p_Descripcion, 'ACTIVO', 'NO'
    );

    IF p_Participantes_JSON IS NOT NULL AND JSON_LENGTH(p_Participantes_JSON) > 0 THEN
        INSERT INTO Participa (Cod_Profesor, Cod_Estudiante, AIP, Fecha_Inicio, Fecha_Fin, Rol)
        SELECT
            NULLIF(TRIM(COALESCE(jt.prof1, jt.prof2)), ''),
            NULLIF(TRIM(COALESCE(jt.est1, jt.est2)), ''),
            TRIM(p_AIP),
            COALESCE(STR_TO_DATE(NULLIF(TRIM(COALESCE(jt.fIni1, jt.fIni2)), ''), '%Y-%m-%d'), p_Fecha_Inicio),
            NULL,
            UPPER(TRIM(COALESCE(jt.rol1, jt.rol2)))
        FROM JSON_TABLE(
            p_Participantes_JSON,
            '$[*]' COLUMNS (
                prof1 VARCHAR(12) PATH '$.Cod_Profesor',
                prof2 VARCHAR(12) PATH '$.codProfesor',
                est1  VARCHAR(12) PATH '$.Cod_Estudiante',
                est2  VARCHAR(12) PATH '$.codEstudiante',
                rol1  VARCHAR(15) PATH '$.Rol',
                rol2  VARCHAR(15) PATH '$.rol',
                fIni1 VARCHAR(20) PATH '$.Fecha_Inicio',
                fIni2 VARCHAR(20) PATH '$.fechaInicio'
            )
        ) AS jt;
    END IF;

    IF p_Lineas_JSON IS NOT NULL AND JSON_LENGTH(p_Lineas_JSON) > 0 THEN
        INSERT INTO Incluye (AIP, Cod_Linea)
        SELECT
            TRIM(p_AIP),
            TRIM(COALESCE(jt.lin1, jt.lin2, jt.linStr))
        FROM JSON_TABLE(
            p_Lineas_JSON,
            '$[*]' COLUMNS (
                lin1   VARCHAR(12) PATH '$.Cod_Linea',
                lin2   VARCHAR(12) PATH '$.codLinea',
                linStr VARCHAR(12) PATH '$'
            )
        ) AS jt
        WHERE COALESCE(jt.lin1, jt.lin2, jt.linStr) IS NOT NULL
          AND TRIM(COALESCE(jt.lin1, jt.lin2, jt.linStr)) <> '';
    END IF;

    INSERT INTO auditoria_operaciones (Operacion, Procedimiento, Resultado, Detalle)
    VALUES ('REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'EXITOSA', CONCAT('Proyecto registrado: ', p_AIP));

    COMMIT;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_operaciones`
--

CREATE TABLE IF NOT EXISTS `auditoria_operaciones` (
  `Id_Auditoria` bigint(20) NOT NULL AUTO_INCREMENT,
  `Fecha` datetime NOT NULL DEFAULT current_timestamp(),
  `Usuario_BD` varchar(128) NOT NULL DEFAULT current_user(),
  `Operacion` varchar(120) NOT NULL,
  `Procedimiento` varchar(120) NOT NULL,
  `Resultado` varchar(20) NOT NULL,
  `Detalle` text DEFAULT NULL,
  PRIMARY KEY (`Id_Auditoria`)
) ;

--
-- Volcado de datos para la tabla `auditoria_operaciones`
--

INSERT INTO `auditoria_operaciones` (`Id_Auditoria`, `Fecha`, `Usuario_BD`, `Operacion`, `Procedimiento`, `Resultado`, `Detalle`) VALUES
(1, '2026-11-25 22:41:59', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(2, '2026-11-25 22:42:27', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(3, '2026-11-25 22:42:44', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(4, '2026-11-25 22:42:48', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(5, '2026-11-25 22:43:06', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(6, '2026-11-25 22:59:02', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(7, '2026-11-25 23:00:59', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(8, '2026-11-25 23:01:01', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(9, '2026-11-25 23:01:01', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(10, '2026-11-25 23:01:01', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(11, '2026-11-25 23:01:01', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(12, '2026-11-25 23:01:04', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(13, '2026-11-25 23:01:07', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(14, '2026-11-25 23:01:16', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(15, '2026-11-25 23:04:17', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(16, '2026-11-25 23:04:20', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(17, '2026-11-25 23:04:20', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(18, '2026-11-25 23:04:20', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(19, '2026-11-25 23:04:20', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(20, '2026-11-25 23:04:20', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(21, '2026-11-25 23:04:24', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(22, '2026-11-25 23:04:24', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(23, '2026-11-25 23:04:25', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(24, '2026-11-25 23:04:27', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(25, '2026-11-25 23:04:34', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(26, '2026-11-25 23:04:34', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(27, '2026-11-25 23:06:08', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(28, '2026-11-25 23:07:06', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(29, '2026-11-25 23:09:37', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo en UEB-INV-104 | JSON recibido: [{\"Cod_Profesor\":\"DOC004\",\"Rol\":\"DIRECTOR\"},{\"Cod_Profesor\":\"DOC005\",\"Rol\":\"SUBROGANTE\"},{\"Cod_Profesor\":\"DOC006\",\"Rol\":\"INVESTIGADOR\"}]'),
(30, '2026-11-25 23:09:39', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo en UEB-INV-104 | JSON recibido: [{\"Cod_Profesor\":\"DOC004\",\"Rol\":\"DIRECTOR\"},{\"Cod_Profesor\":\"DOC005\",\"Rol\":\"SUBROGANTE\"},{\"Cod_Profesor\":\"DOC006\",\"Rol\":\"INVESTIGADOR\"}]'),
(31, '2026-11-25 23:09:39', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo en UEB-INV-104 | JSON recibido: [{\"Cod_Profesor\":\"DOC004\",\"Rol\":\"DIRECTOR\"},{\"Cod_Profesor\":\"DOC005\",\"Rol\":\"SUBROGANTE\"},{\"Cod_Profesor\":\"DOC006\",\"Rol\":\"INVESTIGADOR\"}]'),
(32, '2026-11-25 23:09:40', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo en UEB-INV-104 | JSON recibido: [{\"Cod_Profesor\":\"DOC004\",\"Rol\":\"DIRECTOR\"},{\"Cod_Profesor\":\"DOC005\",\"Rol\":\"SUBROGANTE\"},{\"Cod_Profesor\":\"DOC006\",\"Rol\":\"INVESTIGADOR\"}]'),
(33, '2026-11-25 23:09:40', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo en UEB-INV-104 | JSON recibido: [{\"Cod_Profesor\":\"DOC004\",\"Rol\":\"DIRECTOR\"},{\"Cod_Profesor\":\"DOC005\",\"Rol\":\"SUBROGANTE\"},{\"Cod_Profesor\":\"DOC006\",\"Rol\":\"INVESTIGADOR\"}]'),
(34, '2026-11-25 23:13:22', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-104'),
(35, '2026-11-25 23:18:55', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'EXITOSA', 'Proyecto registrado: UEB-INV-104'),
(36, '2026-11-26 13:41:55', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(37, '2026-11-26 13:42:25', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(38, '2026-11-26 13:42:26', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(39, '2026-11-26 13:42:26', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(40, '2026-11-26 13:42:26', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(41, '2026-11-26 13:42:26', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(42, '2026-11-26 13:42:26', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(43, '2026-11-26 13:42:27', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(44, '2026-11-26 13:42:27', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(45, '2026-11-26 13:42:27', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC007'),
(46, '2026-11-26 13:43:31', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando UEB-INV-104 a DOC008'),
(47, '2026-11-26 13:45:25', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'EXITOSA', 'Asignado DOC008 (INVESTIGADOR) en UEB-INV-104'),
(48, '2026-11-26 13:48:56', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC008 -> DOC007'),
(49, '2026-11-26 13:49:52', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'EXITOSA', 'Asignado DOC007 (INVESTIGADOR) en UEB-INV-104'),
(50, '2026-11-26 13:49:59', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC004 -> DOC007'),
(51, '2026-11-26 13:50:11', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando DOC007 a UEB-INV-104'),
(52, '2026-11-26 13:50:16', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC004 -> DOC007'),
(53, '2026-11-26 13:50:27', 'yosij@localhost', 'ASIGNAR_INVESTIGADOR', 'sp_tx_asignar_investigador', 'ERROR', 'Fallo asignando DOC009 a UEB-INV-104'),
(54, '2026-11-26 13:50:59', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC008 -> DOC007'),
(55, '2026-11-26 13:51:14', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC004 -> DOC005'),
(56, '2026-11-26 13:51:16', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC004 -> DOC005'),
(57, '2026-11-26 13:51:35', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC005 -> DOC006'),
(58, '2026-11-26 13:54:54', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'ERROR', 'Fallo relevo en UEB-INV-104: DOC004 -> DOC005'),
(59, '2026-11-26 13:55:10', 'yosij@localhost', 'CAMBIAR_PERSONAL', 'sp_tx_cambiar_personal', 'EXITOSA', 'Relevo en UEB-INV-104: DOC008 -> DOC009'),
(60, '2026-11-26 14:00:52', 'yosij@localhost', 'REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'ERROR', 'Fallo al registrar producto en UEB-INV-104'),
(61, '2026-11-26 14:01:56', 'yosij@localhost', 'REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'ERROR', 'Fallo al registrar producto en UEB-INV-104'),
(62, '2026-11-26 14:04:58', 'yosij@localhost', 'REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'ERROR', 'Fallo al registrar producto en UEB-INV-104'),
(63, '2026-11-26 14:07:35', 'yosij@localhost', 'REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'ERROR', 'Fallo al registrar producto en UEB-INV-104'),
(64, '2026-11-26 14:08:40', 'yosij@localhost', 'REGISTRAR_PRODUCTO', 'sp_tx_registrar_producto', 'EXITOSA', 'Producto #1 registrado en UEB-INV-104'),
(65, '2026-11-26 14:14:07', 'yosij@localhost', 'APROBAR_PRORROGA', 'sp_tx_aprobar_prorroga', 'ERROR', 'Fallo aprobando prórroga PROR103'),
(66, '2026-11-26 14:14:59', 'yosij@localhost', 'APROBAR_PRORROGA', 'sp_tx_aprobar_prorroga', 'EXITOSA', 'Prórroga PROR102 aprobada para UEB-INV-102'),
(67, '2026-11-26 14:22:53', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-105'),
(68, '2026-11-26 14:25:09', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-105'),
(69, '2026-11-26 14:26:38', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-105'),
(70, '2026-11-26 14:27:23', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-105'),
(71, '2026-11-26 14:38:50', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'ERROR', 'Fallo al registrar proyecto UEB-INV-105'),
(72, '2026-11-26 14:39:35', 'yosij@localhost', 'REGISTRAR_PROYECTO', 'sp_tx_registrar_proyecto', 'EXITOSA', 'Proyecto registrado: UEB-INV-105');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `AUDITORIA_PROYECTOS`
--

CREATE TABLE IF NOT EXISTS `AUDITORIA_PROYECTOS` (
  `Id_Auditoria` bigint(20) NOT NULL AUTO_INCREMENT,
  `Usuario` varchar(128) NOT NULL,
  `Fecha_Hora` datetime NOT NULL DEFAULT current_timestamp(),
  `Operacion` varchar(10) NOT NULL,
  `AIP` varchar(20) NOT NULL,
  `Datos_Anteriores` longtext DEFAULT NULL,
  `Datos_Nuevos` longtext DEFAULT NULL,
  PRIMARY KEY (`Id_Auditoria`),
  KEY `ix_audproy_aip` (`AIP`),
  KEY `ix_audproy_fecha` (`Fecha_Hora`)
) ;

--
-- Volcado de datos para la tabla `AUDITORIA_PROYECTOS`
--

INSERT INTO `AUDITORIA_PROYECTOS` (`Id_Auditoria`, `Usuario`, `Fecha_Hora`, `Operacion`, `AIP`, `Datos_Anteriores`, `Datos_Nuevos`) VALUES
(35, 'director_ueb@localhost', '2026-11-25 23:18:55', 'INSERT', 'UEB-INV-104', NULL, '{\"AIP\": \"UEB-INV-104\", \"Nombre\": \"Plataforma de concientizacion y aprendizaje de proteccion medio ambiental\", \"Acronimo\": \"PCA-AMBIENTAL\", \"Cod_Programa\": \"PROG002\", \"Cod_Finanza\": null, \"Fecha_Inicio\": \"2025-11-11\", \"Fecha_Fin\": \"2026-08-11\", \"Descripcion_Objetivos\": \"Desarrollar una plataforma de aprendizaje y concientizacion\", \"Estado_Proyecto\": \"ACTIVO\", \"Calificacion_Cumplimiento\": null, \"Observaciones\": null, \"Tiene_Prorroga\": \"NO\"}'),
(36, 'director_ueb@localhost', '2026-11-26 14:14:59', 'UPDATE', 'UEB-INV-102', '{\"AIP\": \"UEB-INV-102\", \"Nombre\": \"Plataforma de seguimiento de proyectos institucionales\", \"Acronimo\": \"SEGUI-INV\", \"Cod_Programa\": \"PROG001\", \"Cod_Finanza\": \"FIN002\", \"Fecha_Inicio\": \"2026-04-01\", \"Fecha_Fin\": \"2027-03-31\", \"Descripcion_Objetivos\": \"Desarrollar una plataforma para seguimiento de proyectos y resultados.\", \"Estado_Proyecto\": \"ACTIVO\", \"Calificacion_Cumplimiento\": null, \"Observaciones\": null, \"Tiene_Prorroga\": \"NO\"}', '{\"AIP\": \"UEB-INV-102\", \"Nombre\": \"Plataforma de seguimiento de proyectos institucionales\", \"Acronimo\": \"SEGUI-INV\", \"Cod_Programa\": \"PROG001\", \"Cod_Finanza\": \"FIN002\", \"Fecha_Inicio\": \"2026-04-01\", \"Fecha_Fin\": \"2027-06-30\", \"Descripcion_Objetivos\": \"Desarrollar una plataforma para seguimiento de proyectos y resultados.\", \"Estado_Proyecto\": \"ACTIVO\", \"Calificacion_Cumplimiento\": null, \"Observaciones\": null, \"Tiene_Prorroga\": \"SI\"}'),
(40, 'director_ueb@localhost', '2026-11-26 14:39:35', 'INSERT', 'UEB-INV-105', NULL, '{\"AIP\": \"UEB-INV-105\", \"Nombre\": \"Estudio de emprendiemientos en la ciudad de Guaranda\", \"Acronimo\": \"EMP-GDA\", \"Cod_Programa\": \"PROG002\", \"Cod_Finanza\": null, \"Fecha_Inicio\": \"2025-12-05\", \"Fecha_Fin\": \"2026-07-10\", \"Descripcion_Objetivos\": \"Caso de estudio emprendimientos y productividad en la ciudad de Guaranda\", \"Estado_Proyecto\": \"ACTIVO\", \"Calificacion_Cumplimiento\": null, \"Observaciones\": null, \"Tiene_Prorroga\": \"NO\"}');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Clasificacion_Revista`
--

CREATE TABLE IF NOT EXISTS `Clasificacion_Revista` (
  `Clase` varchar(3) NOT NULL,
  `Indice_Valoracion` decimal(4,2) NOT NULL,
  PRIMARY KEY (`Clase`)
) ;

--
-- Volcado de datos para la tabla `Clasificacion_Revista`
--

INSERT INTO `Clasificacion_Revista` (`Clase`, `Indice_Valoracion`) VALUES
('Q1', 1.00),
('Q2', 0.80),
('Q3', 0.60),
('Q4', 0.40),
('Q5', 0.20);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Desarrolla`
--

CREATE TABLE IF NOT EXISTS `Desarrolla` (
  `Cod_Profesor` varchar(12) NOT NULL,
  `Cod_Linea` varchar(12) NOT NULL,
  PRIMARY KEY (`Cod_Profesor`,`Cod_Linea`),
  KEY `ix_desarrolla_linea` (`Cod_Linea`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Desarrolla`
--

INSERT INTO `Desarrolla` (`Cod_Profesor`, `Cod_Linea`) VALUES
('DOC001', 'LIN001'),
('DOC002', 'LIN001'),
('DOC004', 'LIN001'),
('DOC009', 'LIN001'),
('DOC001', 'LIN002'),
('DOC002', 'LIN002'),
('DOC003', 'LIN002'),
('DOC005', 'LIN002'),
('DOC006', 'LIN002'),
('DOC007', 'LIN002'),
('DOC010', 'LIN002'),
('DOC004', 'LIN003'),
('DOC005', 'LIN003'),
('DOC006', 'LIN003'),
('DOC007', 'LIN003'),
('DOC008', 'LIN003'),
('DOC009', 'LIN003'),
('DOC003', 'LIN004'),
('DOC008', 'LIN004'),
('DOC010', 'LIN005');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Descriptor_Linea`
--

CREATE TABLE IF NOT EXISTS `Descriptor_Linea` (
  `Cod_Linea` varchar(12) NOT NULL,
  `Descriptor` varchar(150) NOT NULL,
  PRIMARY KEY (`Cod_Linea`,`Descriptor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Descriptor_Linea`
--

INSERT INTO `Descriptor_Linea` (`Cod_Linea`, `Descriptor`) VALUES
('LIN001', 'Aprendizaje automático'),
('LIN001', 'Sistemas inteligentes'),
('LIN002', 'Calidad de software'),
('LIN002', 'Desarrollo de aplicaciones'),
('LIN003', 'Analítica institucional'),
('LIN003', 'Bases de datos'),
('LIN004', 'Monitoreo ambiental'),
('LIN005', 'Desarrollo local');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Dominio_Conocimiento`
--

CREATE TABLE IF NOT EXISTS `Dominio_Conocimiento` (
  `Id_Dominio` varchar(12) NOT NULL,
  `Nombre` varchar(120) NOT NULL,
  `Descripcion` text NOT NULL,
  PRIMARY KEY (`Id_Dominio`),
  UNIQUE KEY `uq_dominio_nombre` (`Nombre`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Dominio_Conocimiento`
--

INSERT INTO `Dominio_Conocimiento` (`Id_Dominio`, `Nombre`, `Descripcion`) VALUES
('DOM001', 'Tecnologías de la información', 'Sistemas de información y tecnologías digitales.'),
('DOM002', 'Ambiente y sostenibilidad', 'Investigación ambiental y gestión de recursos naturales.'),
('DOM003', 'Desarrollo territorial', 'Estudios aplicados al desarrollo de la provincia.');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Escribe`
--

CREATE TABLE IF NOT EXISTS `Escribe` (
  `Cod_Profesor` varchar(12) NOT NULL,
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `Cod_Linea` varchar(12) NOT NULL,
  PRIMARY KEY (`Cod_Profesor`,`AIP`,`N_Secuencia`),
  KEY `ix_escribe_producto` (`AIP`,`N_Secuencia`),
  KEY `ix_escribe_linea` (`Cod_Linea`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Escribe`
--

INSERT INTO `Escribe` (`Cod_Profesor`, `AIP`, `N_Secuencia`, `Cod_Linea`) VALUES
('DOC001', 'UEB-INV-101', 1, 'LIN001'),
('DOC002', 'UEB-INV-101', 1, 'LIN001'),
('DOC004', 'UEB-INV-101', 2, 'LIN001'),
('DOC009', 'UEB-INV-102', 2, 'LIN001'),
('DOC001', 'UEB-INV-101', 3, 'LIN002'),
('DOC003', 'UEB-INV-101', 2, 'LIN002'),
('DOC005', 'UEB-INV-104', 1, 'LIN002'),
('DOC006', 'UEB-INV-102', 1, 'LIN002'),
('DOC006', 'UEB-INV-104', 1, 'LIN002'),
('DOC007', 'UEB-INV-104', 1, 'LIN002'),
('DOC010', 'UEB-INV-102', 3, 'LIN002'),
('DOC007', 'UEB-INV-102', 1, 'LIN003'),
('DOC008', 'UEB-INV-102', 2, 'LIN003'),
('DOC001', 'UEB-INV-103', 2, 'LIN004'),
('DOC003', 'UEB-INV-103', 2, 'LIN004');

--
-- Disparadores `Escribe`
--
DELIMITER $$
CREATE TRIGGER `bi_escribe_validar` BEFORE INSERT ON `Escribe` FOR EACH ROW BEGIN
    DECLARE v_ok INT DEFAULT 0;

    -- 1. Comprobar que el autor tenga participación formal
    -- durante el período del proyecto.
    SELECT COUNT(*) INTO v_ok
    FROM Participa p
    JOIN Proyecto_de_Investigacion pr
        ON pr.AIP = p.AIP
    WHERE p.Cod_Profesor = NEW.Cod_Profesor
      AND p.AIP = NEW.AIP
      AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
      AND p.Fecha_Inicio <= pr.Fecha_Fin
      AND COALESCE(p.Fecha_Fin,'9999-12-31') >= pr.Fecha_Inicio;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
        'El autor no tiene participación formal registrada en el proyecto.';
    END IF;

    -- 2. Comprobar que el autor desarrolle la línea
    -- y que esta esté incluida en el proyecto.
    SELECT COUNT(*) INTO v_ok
    FROM Desarrolla d
    JOIN Incluye i
        ON i.Cod_Linea = d.Cod_Linea
    WHERE d.Cod_Profesor = NEW.Cod_Profesor
      AND d.Cod_Linea = NEW.Cod_Linea
      AND i.AIP = NEW.AIP;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
        'La línea debe ser desarrollada por el autor e incluida en el proyecto.';
    END IF;

END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `bu_escribe_validar` BEFORE UPDATE ON `Escribe` FOR EACH ROW BEGIN
    DECLARE v_ok INT DEFAULT 0;

    -- 1. Comprobar la participación formal durante
    -- el período del proyecto.
    SELECT COUNT(*) INTO v_ok
    FROM Participa p
    JOIN Proyecto_de_Investigacion pr
        ON pr.AIP = p.AIP
    WHERE p.Cod_Profesor = NEW.Cod_Profesor
      AND p.AIP = NEW.AIP
      AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
      AND p.Fecha_Inicio <= pr.Fecha_Fin
      AND COALESCE(p.Fecha_Fin,'9999-12-31') >= pr.Fecha_Inicio;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
        'El autor no tiene participación formal registrada en el proyecto.';
    END IF;

    -- 2. Comprobar la línea de investigación.
    SELECT COUNT(*) INTO v_ok
    FROM Desarrolla d
    JOIN Incluye i
        ON i.Cod_Linea = d.Cod_Linea
    WHERE d.Cod_Profesor = NEW.Cod_Profesor
      AND d.Cod_Linea = NEW.Cod_Linea
      AND i.AIP = NEW.AIP;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
        'La línea debe ser desarrollada por el autor e incluida en el proyecto.';
    END IF;

END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Estudiantes`
--

CREATE TABLE IF NOT EXISTS `Estudiantes` (
  `Cod_Estudiante` varchar(12) NOT NULL,
  `Nombres_Apellidos` varchar(160) NOT NULL,
  `Telefono` varchar(20) NOT NULL,
  `Ciclo_Academico` varchar(20) NOT NULL,
  `Cedula_Identidad` varchar(20) NOT NULL,
  PRIMARY KEY (`Cod_Estudiante`),
  UNIQUE KEY `uq_estudiante_cedula` (`Cedula_Identidad`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Estudiantes`
--

INSERT INTO `Estudiantes` (`Cod_Estudiante`, `Nombres_Apellidos`, `Telefono`, `Ciclo_Academico`, `Cedula_Identidad`) VALUES
('EST001', 'Valeria Belén Cárdenas', '0982000001', 'Octavo', '0200000001'),
('EST002', 'Mateo Alejandro Galarza', '0982000002', 'Séptimo', '0200000002'),
('EST003', 'Camila Fernanda Zurita', '0982000003', 'Noveno', '0200000003');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Finanzas`
--

CREATE TABLE IF NOT EXISTS `Finanzas` (
  `Cod_Finanza` varchar(12) NOT NULL,
  `Presupuesto_Inicial` decimal(12,2) NOT NULL DEFAULT 0.00,
  `Gastos` decimal(12,2) NOT NULL DEFAULT 0.00,
  `Presupuesto_Total` decimal(12,2) NOT NULL DEFAULT 0.00,
  `Justificacion` text NOT NULL,
  PRIMARY KEY (`Cod_Finanza`)
) ;

--
-- Volcado de datos para la tabla `Finanzas`
--

INSERT INTO `Finanzas` (`Cod_Finanza`, `Presupuesto_Inicial`, `Gastos`, `Presupuesto_Total`, `Justificacion`) VALUES
('FIN001', 24000.00, 6500.00, 24000.00, 'Presupuesto de investigación educativa y tecnología.'),
('FIN002', 18500.00, 4200.00, 18500.00, 'Presupuesto para monitoreo y análisis de datos.');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Incluye`
--

CREATE TABLE IF NOT EXISTS `Incluye` (
  `AIP` varchar(20) NOT NULL,
  `Cod_Linea` varchar(12) NOT NULL,
  PRIMARY KEY (`AIP`,`Cod_Linea`),
  KEY `ix_incluye_linea` (`Cod_Linea`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Incluye`
--

INSERT INTO `Incluye` (`AIP`, `Cod_Linea`) VALUES
('UEB-INV-101', 'LIN001'),
('UEB-INV-101', 'LIN002'),
('UEB-INV-102', 'LIN002'),
('UEB-INV-104', 'LIN002'),
('UEB-INV-101', 'LIN003'),
('UEB-INV-102', 'LIN003'),
('UEB-INV-105', 'LIN003'),
('UEB-INV-103', 'LIN004'),
('UEB-INV-103', 'LIN005'),
('UEB-INV-105', 'LIN005');

--
-- Disparadores `Incluye`
--
DELIMITER $$
CREATE TRIGGER `bi_incluye_validar` BEFORE INSERT ON `Incluye` FOR EACH ROW BEGIN
  DECLARE v_ok INT DEFAULT 0;

  SELECT COUNT(*) INTO v_ok
  FROM Participa p
  JOIN Desarrolla d ON d.Cod_Profesor=p.Cod_Profesor
  JOIN Proyecto_de_Investigacion pr ON pr.AIP=p.AIP
  WHERE p.AIP=NEW.AIP
    AND d.Cod_Linea=NEW.Cod_Linea
    AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
    AND p.Fecha_Inicio <= pr.Fecha_Fin
    AND COALESCE(p.Fecha_Fin,'9999-12-31') >= pr.Fecha_Inicio;

  IF v_ok=0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='La línea incluida debe ser desarrollada por al menos un docente del proyecto.';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Libros`
--

CREATE TABLE IF NOT EXISTS `Libros` (
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `ISBN` varchar(20) NOT NULL,
  `Editorial` varchar(150) NOT NULL,
  `Anio_Publicacion` smallint(6) NOT NULL,
  PRIMARY KEY (`AIP`,`N_Secuencia`),
  UNIQUE KEY `uq_libro_isbn` (`ISBN`)
) ;

--
-- Volcado de datos para la tabla `Libros`
--

INSERT INTO `Libros` (`AIP`, `N_Secuencia`, `ISBN`, `Editorial`, `Anio_Publicacion`) VALUES
('UEB-INV-101', 3, '9789942000001', 'Editorial Universitaria Andina', 2026);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Linea_Investigacion`
--

CREATE TABLE IF NOT EXISTS `Linea_Investigacion` (
  `Cod_Linea` varchar(12) NOT NULL,
  `Nombre` varchar(150) NOT NULL,
  `Id_Dominio` varchar(12) NOT NULL,
  PRIMARY KEY (`Cod_Linea`),
  UNIQUE KEY `uq_linea_nombre` (`Nombre`),
  KEY `fk_linea_dominio` (`Id_Dominio`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Linea_Investigacion`
--

INSERT INTO `Linea_Investigacion` (`Cod_Linea`, `Nombre`, `Id_Dominio`) VALUES
('LIN001', 'Inteligencia artificial aplicada', 'DOM001'),
('LIN002', 'Ingeniería de software', 'DOM001'),
('LIN003', 'Gestión y analítica de datos', 'DOM001'),
('LIN004', 'Gestión de recursos hídricos', 'DOM002'),
('LIN005', 'Innovación y desarrollo territorial', 'DOM003');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Participa`
--

CREATE TABLE IF NOT EXISTS `Participa` (
  `Id_Participacion` bigint(20) NOT NULL AUTO_INCREMENT,
  `Cod_Profesor` varchar(12) DEFAULT NULL,
  `Cod_Estudiante` varchar(12) DEFAULT NULL,
  `AIP` varchar(20) NOT NULL,
  `Fecha_Inicio` date NOT NULL,
  `Fecha_Fin` date DEFAULT NULL,
  `Rol` varchar(15) NOT NULL,
  PRIMARY KEY (`Id_Participacion`),
  KEY `ix_participa_profesor` (`Cod_Profesor`,`AIP`,`Fecha_Inicio`),
  KEY `ix_participa_estudiante` (`Cod_Estudiante`,`AIP`,`Fecha_Inicio`),
  KEY `ix_participa_proyecto` (`AIP`)
) ;

--
-- Volcado de datos para la tabla `Participa`
--

INSERT INTO `Participa` (`Id_Participacion`, `Cod_Profesor`, `Cod_Estudiante`, `AIP`, `Fecha_Inicio`, `Fecha_Fin`, `Rol`) VALUES
(1, 'DOC001', NULL, 'UEB-INV-101', '2026-03-01', NULL, 'DIRECTOR'),
(2, 'DOC002', NULL, 'UEB-INV-101', '2026-03-01', NULL, 'SUBROGANTE'),
(3, 'DOC003', NULL, 'UEB-INV-101', '2026-03-01', NULL, 'INVESTIGADOR'),
(4, 'DOC004', NULL, 'UEB-INV-101', '2026-03-15', NULL, 'INVESTIGADOR'),
(5, 'DOC005', NULL, 'UEB-INV-101', '2026-04-01', NULL, 'INVESTIGADOR'),
(6, NULL, 'EST001', 'UEB-INV-101', '2026-05-01', NULL, 'ESTUDIANTE'),
(7, 'DOC006', NULL, 'UEB-INV-102', '2026-04-01', NULL, 'DIRECTOR'),
(8, 'DOC007', NULL, 'UEB-INV-102', '2026-04-01', NULL, 'SUBROGANTE'),
(9, 'DOC008', NULL, 'UEB-INV-102', '2026-04-01', NULL, 'INVESTIGADOR'),
(10, 'DOC009', NULL, 'UEB-INV-102', '2026-04-10', NULL, 'INVESTIGADOR'),
(11, 'DOC010', NULL, 'UEB-INV-102', '2026-05-01', NULL, 'INVESTIGADOR'),
(12, NULL, 'EST002', 'UEB-INV-102', '2026-05-01', NULL, 'ESTUDIANTE'),
(13, 'DOC001', NULL, 'UEB-INV-103', '2025-02-01', '2026-12-31', 'DIRECTOR'),
(14, 'DOC002', NULL, 'UEB-INV-103', '2025-02-01', '2026-12-31', 'SUBROGANTE'),
(15, 'DOC003', NULL, 'UEB-INV-103', '2025-02-01', '2026-12-31', 'INVESTIGADOR'),
(16, NULL, 'EST003', 'UEB-INV-103', '2025-04-01', '2026-12-31', 'ESTUDIANTE'),
(20, 'DOC004', NULL, 'UEB-INV-104', '2025-11-11', NULL, 'DIRECTOR'),
(21, 'DOC005', NULL, 'UEB-INV-104', '2025-11-11', NULL, 'SUBROGANTE'),
(22, 'DOC006', NULL, 'UEB-INV-104', '2025-11-11', NULL, 'INVESTIGADOR'),
(23, 'DOC008', NULL, 'UEB-INV-104', '2025-11-14', '2025-11-19', 'INVESTIGADOR'),
(24, 'DOC007', NULL, 'UEB-INV-104', '2025-11-12', NULL, 'INVESTIGADOR'),
(25, 'DOC009', NULL, 'UEB-INV-104', '2025-11-20', NULL, 'INVESTIGADOR'),
(28, 'DOC010', NULL, 'UEB-INV-105', '2025-12-05', NULL, 'DIRECTOR'),
(29, 'DOC008', NULL, 'UEB-INV-105', '2025-12-05', NULL, 'SUBROGANTE'),
(30, NULL, 'EST002', 'UEB-INV-105', '2025-12-05', NULL, 'ESTUDIANTE');

--
-- Disparadores `Participa`
--
DELIMITER $$
CREATE TRIGGER `bi_participa_validar` BEFORE INSERT ON `Participa` FOR EACH ROW BEGIN
  DECLARE v_estado VARCHAR(15);
  DECLARE v_formales INT DEFAULT 0;
  DECLARE v_directores INT DEFAULT 0;
  DECLARE v_subrogantes INT DEFAULT 0;
  DECLARE v_investigadores INT DEFAULT 0;
  DECLARE v_proyectos INT DEFAULT 0;
  DECLARE v_solapados INT DEFAULT 0;

  -- 1. Validar que exista exactamente un tipo de participante.
  IF (
      (NEW.Cod_Profesor IS NULL AND NEW.Cod_Estudiante IS NULL)
      OR
      (NEW.Cod_Profesor IS NOT NULL AND NEW.Cod_Estudiante IS NOT NULL)
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
      'Debe registrarse un profesor o un estudiante, pero no ambos.';
  END IF;

  -- 2. Validar que el rol corresponda al participante.
  IF (
      NEW.Cod_Profesor IS NOT NULL
      AND NEW.Rol NOT IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
  ) OR (
      NEW.Cod_Estudiante IS NOT NULL
      AND NEW.Rol <> 'ESTUDIANTE'
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
      'El rol no corresponde al tipo de participante.';
  END IF;

  -- 3. Comprobar que exista el proyecto.
  SELECT Estado_Proyecto INTO v_estado
  FROM Proyecto_de_Investigacion
  WHERE AIP = NEW.AIP;

  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT='El proyecto no existe.';
  END IF;

  -- 4. Validaciones para docentes.
  IF NEW.Cod_Profesor IS NOT NULL THEN

    SELECT COUNT(*) INTO v_solapados
    FROM Participa p
    WHERE p.Cod_Profesor = NEW.Cod_Profesor
      AND p.AIP = NEW.AIP
      AND p.Rol <> 'ESTUDIANTE'
      AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
      AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

    IF v_solapados > 0 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT='El docente ya tiene una participación coincidente en este proyecto.';
    END IF;

    IF NEW.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR') THEN

      SELECT COUNT(DISTINCT Cod_Profesor) INTO v_formales
      FROM Participa p
      WHERE p.AIP = NEW.AIP
        AND p.Cod_Profesor IS NOT NULL
        AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
        AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
        AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

      IF v_formales >= 5 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT='El proyecto admite máximo cinco docentes formales.';
      END IF;

      SELECT COUNT(*) INTO v_directores
      FROM Participa p
      WHERE p.AIP=NEW.AIP
        AND p.Rol='DIRECTOR'
        AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
        AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

      SELECT COUNT(*) INTO v_subrogantes
      FROM Participa p
      WHERE p.AIP=NEW.AIP
        AND p.Rol='SUBROGANTE'
        AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
        AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

      SELECT COUNT(*) INTO v_investigadores
      FROM Participa p
      WHERE p.AIP=NEW.AIP
        AND p.Rol='INVESTIGADOR'
        AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
        AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

      IF NEW.Rol='DIRECTOR' AND v_directores >= 1 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT='Ya existe un director en ese período.';
      END IF;

      IF NEW.Rol='SUBROGANTE' AND v_subrogantes >= 1 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT='Ya existe un subrogante en ese período.';
      END IF;

      IF NEW.Rol='INVESTIGADOR' AND v_investigadores >= 3 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT='El proyecto admite máximo tres investigadores.';
      END IF;

      -- 5. Máximo dos proyectos activos simultáneos por docente.
      IF v_estado='ACTIVO' THEN

        SELECT COUNT(DISTINCT p.AIP) INTO v_proyectos
        FROM Participa p
        JOIN Proyecto_de_Investigacion pr ON pr.AIP=p.AIP
        WHERE p.Cod_Profesor=NEW.Cod_Profesor
          AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
          AND pr.Estado_Proyecto='ACTIVO'
          AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
          AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

        IF v_proyectos >= 2 THEN
          SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT='El docente supera el límite de dos proyectos activos simultáneos.';
        END IF;

      END IF;
    END IF;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `bu_participa_validar` BEFORE UPDATE ON `Participa` FOR EACH ROW BEGIN
  DECLARE v_estado VARCHAR(15);
  DECLARE v_formales INT DEFAULT 0;
  DECLARE v_proyectos INT DEFAULT 0;

  -- 1. Validar que exista exactamente un tipo de participante.
  IF (
      (NEW.Cod_Profesor IS NULL AND NEW.Cod_Estudiante IS NULL)
      OR
      (NEW.Cod_Profesor IS NOT NULL AND NEW.Cod_Estudiante IS NOT NULL)
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
      'Debe registrarse un profesor o un estudiante, pero no ambos.';
  END IF;

  -- 2. Validar que el rol corresponda al participante.
  IF (
      NEW.Cod_Profesor IS NOT NULL
      AND NEW.Rol NOT IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
  ) OR (
      NEW.Cod_Estudiante IS NOT NULL
      AND NEW.Rol <> 'ESTUDIANTE'
  ) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
      'El rol no corresponde al tipo de participante.';
  END IF;

  -- 3. Validar las fechas.
  IF NEW.Fecha_Fin IS NOT NULL
     AND NEW.Fecha_Fin < NEW.Fecha_Inicio THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
      'La fecha final no puede ser anterior a la inicial.';
  END IF;

  -- 4. Consultar el estado del proyecto.
  SELECT Estado_Proyecto INTO v_estado
  FROM Proyecto_de_Investigacion
  WHERE AIP = NEW.AIP;

  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT='El proyecto no existe.';
  END IF;

  -- 5. Validaciones para docentes formales.
  IF NEW.Cod_Profesor IS NOT NULL
     AND NEW.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR') THEN

    -- Máximo cinco docentes formales por período.
    SELECT COUNT(DISTINCT p.Cod_Profesor)
    INTO v_formales
    FROM Participa p
    WHERE p.AIP = NEW.AIP
      AND p.Id_Participacion <> OLD.Id_Participacion
      AND p.Cod_Profesor IS NOT NULL
      AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
      AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
      AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

    IF v_formales >= 5 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT =
        'El proyecto admite máximo cinco docentes formales.';
    END IF;

    -- Máximo dos proyectos activos simultáneos por docente.
    IF v_estado = 'ACTIVO' THEN

      SELECT COUNT(DISTINCT p.AIP)
      INTO v_proyectos
      FROM Participa p
      JOIN Proyecto_de_Investigacion pr
        ON pr.AIP = p.AIP
      WHERE p.Cod_Profesor = NEW.Cod_Profesor
        AND p.Id_Participacion <> OLD.Id_Participacion
        AND p.Rol IN ('DIRECTOR','SUBROGANTE','INVESTIGADOR')
        AND pr.Estado_Proyecto = 'ACTIVO'
        AND NEW.Fecha_Inicio <= COALESCE(p.Fecha_Fin,'9999-12-31')
        AND COALESCE(NEW.Fecha_Fin,'9999-12-31') >= p.Fecha_Inicio;

      IF v_proyectos >= 2 THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT =
          'El docente supera el límite de dos proyectos activos simultáneos.';
      END IF;

    END IF;
  END IF;

END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Patentes`
--

CREATE TABLE IF NOT EXISTS `Patentes` (
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `N_Registro` varchar(45) NOT NULL,
  `Fecha_Registro` date NOT NULL,
  `Estado` varchar(35) NOT NULL,
  PRIMARY KEY (`AIP`,`N_Secuencia`),
  UNIQUE KEY `uq_patente_registro` (`N_Registro`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Patentes`
--

INSERT INTO `Patentes` (`AIP`, `N_Secuencia`, `N_Registro`, `Fecha_Registro`, `Estado`) VALUES
('UEB-INV-102', 3, 'SOL-EC-2026-101', '2026-10-10', 'EN_TRAMITE'),
('UEB-INV-103', 1, 'SOL-EC-2025-014', '2025-09-20', 'CONCEDIDA'),
('UEB-INV-104', 1, 'SOL-EC-2026-111', '2026-12-11', 'EN_TRAMITE');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Productos`
--

CREATE TABLE IF NOT EXISTS `Productos` (
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `Titulo` varchar(250) NOT NULL,
  `Tipo_Publicacion` varchar(12) NOT NULL,
  PRIMARY KEY (`AIP`,`N_Secuencia`)
) ;

--
-- Volcado de datos para la tabla `Productos`
--

INSERT INTO `Productos` (`AIP`, `N_Secuencia`, `Titulo`, `Tipo_Publicacion`) VALUES
('UEB-INV-101', 1, 'Herramientas inteligentes para enseñanza universitaria', 'REVISTA'),
('UEB-INV-101', 2, 'Asistentes educativos en instituciones superiores', 'CONGRESO'),
('UEB-INV-101', 3, 'Aplicaciones educativas de inteligencia artificial', 'LIBRO'),
('UEB-INV-102', 1, 'Arquitectura de seguimiento de proyectos académicos', 'CONGRESO'),
('UEB-INV-102', 2, 'Analítica de proyectos universitarios', 'REVISTA'),
('UEB-INV-102', 3, 'Sistema de clasificación automatizada de informes', 'PATENTE'),
('UEB-INV-103', 1, 'Dispositivo para medición de parámetros del agua', 'PATENTE'),
('UEB-INV-103', 2, 'Caracterización de cuerpos de agua de Bolívar', 'REVISTA'),
('UEB-INV-104', 1, 'Plataforma educativa de concientizacion del medio ambiente', 'PATENTE');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Profesor`
--

CREATE TABLE IF NOT EXISTS `Profesor` (
  `Cod_Profesor` varchar(12) NOT NULL,
  `Nombres_Apellidos` varchar(160) NOT NULL,
  `Telefono` varchar(20) NOT NULL,
  `N_Despacho` varchar(20) NOT NULL,
  PRIMARY KEY (`Cod_Profesor`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Profesor`
--

INSERT INTO `Profesor` (`Cod_Profesor`, `Nombres_Apellidos`, `Telefono`, `N_Despacho`) VALUES
('DOC001', 'María Fernanda López Guamangate', '0991000001', 'B-201'),
('DOC002', 'Carlos Andrés Guaraca Pilamunga', '0991000002', 'B-202'),
('DOC003', 'Ana Belén Paredes Chimbo', '0991000003', 'B-203'),
('DOC004', 'Luis Alberto Yánez Sisa', '0991000004', 'B-204'),
('DOC005', 'Daniela Estefanía Cando Morocho', '0991000005', 'B-205'),
('DOC006', 'Jorge Patricio Sanmartín Vega', '0991000006', 'B-206'),
('DOC007', 'Rosa Elena Salazar Guamán', '0991000007', 'B-207'),
('DOC008', 'Miguel Ángel Núñez Toapanta', '0991000008', 'B-208'),
('DOC009', 'Paola Verónica Chiluisa Mena', '0991000009', 'B-209'),
('DOC010', 'Andrés Sebastián Vinueza Lara', '0991000010', 'B-210');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Programa_Investigacion`
--

CREATE TABLE IF NOT EXISTS `Programa_Investigacion` (
  `Cod_Programa` varchar(12) NOT NULL,
  `Nombre_Programa` varchar(160) NOT NULL,
  `Descripcion` text NOT NULL,
  PRIMARY KEY (`Cod_Programa`),
  UNIQUE KEY `uq_programa_nombre` (`Nombre_Programa`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `Programa_Investigacion`
--

INSERT INTO `Programa_Investigacion` (`Cod_Programa`, `Nombre_Programa`, `Descripcion`) VALUES
('PROG001', 'Transformación digital', 'Programa institucional de innovación y transformación digital.'),
('PROG002', 'Ambiente y territorio', 'Programa de sostenibilidad ambiental y desarrollo territorial.');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Prorroga`
--

CREATE TABLE IF NOT EXISTS `Prorroga` (
  `Cod_Prorroga` varchar(12) NOT NULL,
  `AIP` varchar(20) NOT NULL,
  `Razon_Prorroga` text NOT NULL,
  `Duracion_Meses` tinyint(3) UNSIGNED NOT NULL,
  `Fecha_Inicio` date DEFAULT NULL,
  `Fecha_Fin` date DEFAULT NULL,
  `Estado_Solicitud` varchar(12) NOT NULL DEFAULT 'PENDIENTE',
  `Resolucion` varchar(250) DEFAULT NULL,
  `Fecha_Resolucion` date DEFAULT NULL,
  PRIMARY KEY (`Cod_Prorroga`),
  KEY `ix_prorroga_proyecto` (`AIP`)
) ;

--
-- Volcado de datos para la tabla `Prorroga`
--

INSERT INTO `Prorroga` (`Cod_Prorroga`, `AIP`, `Razon_Prorroga`, `Duracion_Meses`, `Fecha_Inicio`, `Fecha_Fin`, `Estado_Solicitud`, `Resolucion`, `Fecha_Resolucion`) VALUES
('PROR101', 'UEB-INV-101', 'Ampliación para validar los resultados con usuarios.', 2, NULL, NULL, 'PENDIENTE', NULL, NULL),
('PROR102', 'UEB-INV-102', 'Retraso en las pruebas de integración.', 3, '2027-04-01', '2027-06-30', 'APROBADA', 'Extension de plazo por etapa de pruebas en correcion de errores y funcionamiento escalable', '2026-10-30');

--
-- Disparadores `Prorroga`
--
DELIMITER $$
CREATE TRIGGER `bi_prorroga_validar` BEFORE INSERT ON `Prorroga` FOR EACH ROW BEGIN
  IF NEW.Duracion_Meses NOT BETWEEN 1 AND 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='La prórroga debe durar entre uno y tres meses.';
  END IF;

  IF NEW.Estado_Solicitud='APROBADA' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='La solicitud debe registrarse PENDIENTE y aprobarse mediante el proceso correspondiente.';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Proyecto_de_Investigacion`
--

CREATE TABLE IF NOT EXISTS `Proyecto_de_Investigacion` (
  `AIP` varchar(20) NOT NULL,
  `Nombre` varchar(200) NOT NULL,
  `Acronimo` varchar(35) NOT NULL,
  `Cod_Programa` varchar(12) DEFAULT NULL,
  `Cod_Finanza` varchar(12) DEFAULT NULL,
  `Fecha_Inicio` date NOT NULL,
  `Fecha_Fin` date NOT NULL,
  `Descripcion_Objetivos` text NOT NULL,
  `Estado_Proyecto` varchar(15) NOT NULL DEFAULT 'ACTIVO',
  `Calificacion_Cumplimiento` decimal(5,2) DEFAULT NULL,
  `Observaciones` text DEFAULT NULL,
  `Tiene_Prorroga` enum('SI','NO') NOT NULL DEFAULT 'NO',
  PRIMARY KEY (`AIP`),
  UNIQUE KEY `uq_proyecto_nombre` (`Nombre`),
  UNIQUE KEY `uq_proyecto_finanza` (`Cod_Finanza`),
  KEY `ix_proyecto_programa` (`Cod_Programa`)
) ;

--
-- Volcado de datos para la tabla `Proyecto_de_Investigacion`
--

INSERT INTO `Proyecto_de_Investigacion` (`AIP`, `Nombre`, `Acronimo`, `Cod_Programa`, `Cod_Finanza`, `Fecha_Inicio`, `Fecha_Fin`, `Descripcion_Objetivos`, `Estado_Proyecto`, `Calificacion_Cumplimiento`, `Observaciones`, `Tiene_Prorroga`) VALUES
('UEB-INV-101', 'Herramientas inteligentes para el aprendizaje universitario', 'IA-EDU', 'PROG001', 'FIN001', '2026-03-01', '2027-02-28', 'Diseñar herramientas de apoyo educativo basadas en inteligencia artificial.', 'ACTIVO', NULL, NULL, 'NO'),
('UEB-INV-102', 'Plataforma de seguimiento de proyectos institucionales', 'SEGUI-INV', 'PROG001', 'FIN002', '2026-04-01', '2027-06-30', 'Desarrollar una plataforma para seguimiento de proyectos y resultados.', 'ACTIVO', NULL, NULL, 'SI'),
('UEB-INV-103', 'Monitoreo comunitario de recursos hídricos', 'AGUA-UEB', 'PROG002', NULL, '2025-02-01', '2026-12-31', 'Analizar indicadores de calidad de agua en comunidades de Bolívar.', 'FINALIZADO', NULL, NULL, 'NO'),
('UEB-INV-104', 'Plataforma de concientizacion y aprendizaje de proteccion medio ambiental', 'PCA-AMBIENTAL', 'PROG002', NULL, '2025-11-11', '2026-08-11', 'Desarrollar una plataforma de aprendizaje y concientizacion', 'ACTIVO', NULL, NULL, 'NO'),
('UEB-INV-105', 'Estudio de emprendiemientos en la ciudad de Guaranda', 'EMP-GDA', 'PROG002', NULL, '2025-12-05', '2026-07-10', 'Caso de estudio emprendimientos y productividad en la ciudad de Guaranda', 'ACTIVO', NULL, NULL, 'NO');

--
-- Disparadores `Proyecto_de_Investigacion`
--
DELIMITER $$
CREATE TRIGGER `ad_proyecto_auditoria` AFTER DELETE ON `Proyecto_de_Investigacion` FOR EACH ROW BEGIN
  INSERT INTO AUDITORIA_PROYECTOS
    (Usuario, Fecha_Hora, Operacion, AIP, Datos_Anteriores, Datos_Nuevos)
  VALUES
    (USER(), NOW(), 'DELETE', OLD.AIP,
     JSON_OBJECT(
       'AIP', OLD.AIP,
       'Nombre', OLD.Nombre,
       'Acronimo', OLD.Acronimo,
       'Cod_Programa', OLD.Cod_Programa,
       'Cod_Finanza', OLD.Cod_Finanza,
       'Fecha_Inicio', OLD.Fecha_Inicio,
       'Fecha_Fin', OLD.Fecha_Fin,
       'Descripcion_Objetivos', OLD.Descripcion_Objetivos,
       'Estado_Proyecto', OLD.Estado_Proyecto,
       'Calificacion_Cumplimiento', OLD.Calificacion_Cumplimiento,
       'Observaciones', OLD.Observaciones,
       'Tiene_Prorroga', OLD.Tiene_Prorroga),
     NULL);
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `ai_proyecto_auditoria` AFTER INSERT ON `Proyecto_de_Investigacion` FOR EACH ROW BEGIN
  INSERT INTO AUDITORIA_PROYECTOS
    (Usuario, Fecha_Hora, Operacion, AIP, Datos_Anteriores, Datos_Nuevos)
  VALUES
    (USER(), NOW(), 'INSERT', NEW.AIP, NULL,
     JSON_OBJECT(
       'AIP', NEW.AIP,
       'Nombre', NEW.Nombre,
       'Acronimo', NEW.Acronimo,
       'Cod_Programa', NEW.Cod_Programa,
       'Cod_Finanza', NEW.Cod_Finanza,
       'Fecha_Inicio', NEW.Fecha_Inicio,
       'Fecha_Fin', NEW.Fecha_Fin,
       'Descripcion_Objetivos', NEW.Descripcion_Objetivos,
       'Estado_Proyecto', NEW.Estado_Proyecto,
       'Calificacion_Cumplimiento', NEW.Calificacion_Cumplimiento,
       'Observaciones', NEW.Observaciones,
       'Tiene_Prorroga', NEW.Tiene_Prorroga));
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `au_proyecto_auditoria` AFTER UPDATE ON `Proyecto_de_Investigacion` FOR EACH ROW BEGIN
  INSERT INTO AUDITORIA_PROYECTOS
    (Usuario, Fecha_Hora, Operacion, AIP, Datos_Anteriores, Datos_Nuevos)
  VALUES
    (USER(), NOW(), 'UPDATE', OLD.AIP,
     JSON_OBJECT(
       'AIP', OLD.AIP,
       'Nombre', OLD.Nombre,
       'Acronimo', OLD.Acronimo,
       'Cod_Programa', OLD.Cod_Programa,
       'Cod_Finanza', OLD.Cod_Finanza,
       'Fecha_Inicio', OLD.Fecha_Inicio,
       'Fecha_Fin', OLD.Fecha_Fin,
       'Descripcion_Objetivos', OLD.Descripcion_Objetivos,
       'Estado_Proyecto', OLD.Estado_Proyecto,
       'Calificacion_Cumplimiento', OLD.Calificacion_Cumplimiento,
       'Observaciones', OLD.Observaciones,
       'Tiene_Prorroga', OLD.Tiene_Prorroga),
     JSON_OBJECT(
       'AIP', NEW.AIP,
       'Nombre', NEW.Nombre,
       'Acronimo', NEW.Acronimo,
       'Cod_Programa', NEW.Cod_Programa,
       'Cod_Finanza', NEW.Cod_Finanza,
       'Fecha_Inicio', NEW.Fecha_Inicio,
       'Fecha_Fin', NEW.Fecha_Fin,
       'Descripcion_Objetivos', NEW.Descripcion_Objetivos,
       'Estado_Proyecto', NEW.Estado_Proyecto,
       'Calificacion_Cumplimiento', NEW.Calificacion_Cumplimiento,
       'Observaciones', NEW.Observaciones,
       'Tiene_Prorroga', NEW.Tiene_Prorroga));
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Publicacion_Congreso`
--

CREATE TABLE IF NOT EXISTS `Publicacion_Congreso` (
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `Nombre_Congreso` varchar(180) NOT NULL,
  `Tipo_Congreso` varchar(15) NOT NULL,
  `Lugar` varchar(120) NOT NULL,
  `Pais` varchar(80) NOT NULL,
  `Editorial` varchar(150) DEFAULT NULL,
  `Fecha_Inicio` date NOT NULL,
  `Fecha_Final` date NOT NULL,
  PRIMARY KEY (`AIP`,`N_Secuencia`)
) ;

--
-- Volcado de datos para la tabla `Publicacion_Congreso`
--

INSERT INTO `Publicacion_Congreso` (`AIP`, `N_Secuencia`, `Nombre_Congreso`, `Tipo_Congreso`, `Lugar`, `Pais`, `Editorial`, `Fecha_Inicio`, `Fecha_Final`) VALUES
('UEB-INV-101', 2, 'Congreso Ecuatoriano de Innovación Educativa', 'NACIONAL', 'Quito', 'Ecuador', NULL, '2026-08-12', '2026-08-14'),
('UEB-INV-102', 1, 'Encuentro Internacional de Sistemas de Información', 'INTERNACIONAL', 'Cuenca', 'Ecuador', 'Ediciones de Investigación Digital', '2026-09-10', '2026-09-12');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `Publicacion_Revista`
--

CREATE TABLE IF NOT EXISTS `Publicacion_Revista` (
  `AIP` varchar(20) NOT NULL,
  `N_Secuencia` int(11) NOT NULL,
  `Nombre_Revista` varchar(180) NOT NULL,
  `Editorial` varchar(150) NOT NULL,
  `Pagina_Inicio` int(11) NOT NULL,
  `Pagina_Fin` int(11) NOT NULL,
  `Volumen` varchar(20) NOT NULL,
  `Numero_Revista` varchar(20) NOT NULL,
  `Clase` varchar(3) NOT NULL,
  `Categoria_Revista` varchar(30) NOT NULL DEFAULT 'ALTO_IMPACTO',
  PRIMARY KEY (`AIP`,`N_Secuencia`),
  KEY `ix_pubrev_clase` (`Clase`)
) ;

--
-- Volcado de datos para la tabla `Publicacion_Revista`
--

INSERT INTO `Publicacion_Revista` (`AIP`, `N_Secuencia`, `Nombre_Revista`, `Editorial`, `Pagina_Inicio`, `Pagina_Fin`, `Volumen`, `Numero_Revista`, `Clase`, `Categoria_Revista`) VALUES
('UEB-INV-101', 1, 'Revista Andina de Tecnología Educativa', 'Editorial Académica Andina', 15, 30, '8', '2', 'Q1', 'ALTO_IMPACTO'),
('UEB-INV-102', 2, 'Revista de Sistemas Universitarios', 'Ediciones del Conocimiento', 41, 57, '12', '3', 'Q3', 'ALTO_IMPACTO'),
('UEB-INV-103', 2, 'Revista Regional de Ciencia y Territorio', 'Editorial Sierra Centro', 10, 22, '6', '1', 'Q5', 'ALTO_IMPACTO');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_proyectos_doc001`
-- (Véase abajo para la vista actual)
--
CREATE TABLE IF NOT EXISTS `v_proyectos_doc001` (
`AIP` varchar(20)
,`Nombre` varchar(200)
,`Fecha_Inicio` date
,`Fecha_Fin` date
,`Estado_Proyecto` varchar(15)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_proyectos_est001`
-- (Véase abajo para la vista actual)
--
CREATE TABLE IF NOT EXISTS `v_proyectos_est001` (
`AIP` varchar(20)
,`Nombre` varchar(200)
,`Fecha_Inicio` date
,`Fecha_Fin` date
,`Estado_Proyecto` varchar(15)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `v_proyectos_doc001`
--
DROP TABLE IF EXISTS `v_proyectos_doc001`;

CREATE ALGORITHM=UNDEFINED DEFINER=`yosij`@`localhost` SQL SECURITY DEFINER VIEW `v_proyectos_doc001`  AS SELECT DISTINCT `pr`.`AIP` AS `AIP`, `pr`.`Nombre` AS `Nombre`, `pr`.`Fecha_Inicio` AS `Fecha_Inicio`, `pr`.`Fecha_Fin` AS `Fecha_Fin`, `pr`.`Estado_Proyecto` AS `Estado_Proyecto` FROM (`Proyecto_de_Investigacion` `pr` join `Participa` `pa` on(`pa`.`AIP` = `pr`.`AIP`)) WHERE `pa`.`Cod_Profesor` = 'DOC001' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_proyectos_est001`
--
DROP TABLE IF EXISTS `v_proyectos_est001`;

CREATE ALGORITHM=UNDEFINED DEFINER=`yosij`@`localhost` SQL SECURITY DEFINER VIEW `v_proyectos_est001`  AS SELECT DISTINCT `pr`.`AIP` AS `AIP`, `pr`.`Nombre` AS `Nombre`, `pr`.`Fecha_Inicio` AS `Fecha_Inicio`, `pr`.`Fecha_Fin` AS `Fecha_Fin`, `pr`.`Estado_Proyecto` AS `Estado_Proyecto` FROM (`Proyecto_de_Investigacion` `pr` join `Participa` `pa` on(`pa`.`AIP` = `pr`.`AIP`)) WHERE `pa`.`Cod_Estudiante` = 'EST001' ;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `Desarrolla`
--
ALTER TABLE `Desarrolla`
  ADD CONSTRAINT `fk_desarrolla_linea` FOREIGN KEY (`Cod_Linea`) REFERENCES `Linea_Investigacion` (`Cod_Linea`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_desarrolla_profesor` FOREIGN KEY (`Cod_Profesor`) REFERENCES `Profesor` (`Cod_Profesor`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Descriptor_Linea`
--
ALTER TABLE `Descriptor_Linea`
  ADD CONSTRAINT `fk_descriptor_linea` FOREIGN KEY (`Cod_Linea`) REFERENCES `Linea_Investigacion` (`Cod_Linea`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Escribe`
--
ALTER TABLE `Escribe`
  ADD CONSTRAINT `fk_escribe_linea` FOREIGN KEY (`Cod_Linea`) REFERENCES `Linea_Investigacion` (`Cod_Linea`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_escribe_producto` FOREIGN KEY (`AIP`,`N_Secuencia`) REFERENCES `Productos` (`AIP`, `N_Secuencia`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_escribe_profesor` FOREIGN KEY (`Cod_Profesor`) REFERENCES `Profesor` (`Cod_Profesor`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `Incluye`
--
ALTER TABLE `Incluye`
  ADD CONSTRAINT `fk_incluye_linea` FOREIGN KEY (`Cod_Linea`) REFERENCES `Linea_Investigacion` (`Cod_Linea`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_incluye_proyecto` FOREIGN KEY (`AIP`) REFERENCES `Proyecto_de_Investigacion` (`AIP`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Libros`
--
ALTER TABLE `Libros`
  ADD CONSTRAINT `fk_libros_producto` FOREIGN KEY (`AIP`,`N_Secuencia`) REFERENCES `Productos` (`AIP`, `N_Secuencia`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Linea_Investigacion`
--
ALTER TABLE `Linea_Investigacion`
  ADD CONSTRAINT `fk_linea_dominio` FOREIGN KEY (`Id_Dominio`) REFERENCES `Dominio_Conocimiento` (`Id_Dominio`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `Participa`
--
ALTER TABLE `Participa`
  ADD CONSTRAINT `fk_participa_estudiante` FOREIGN KEY (`Cod_Estudiante`) REFERENCES `Estudiantes` (`Cod_Estudiante`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_participa_profesor` FOREIGN KEY (`Cod_Profesor`) REFERENCES `Profesor` (`Cod_Profesor`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_participa_proyecto` FOREIGN KEY (`AIP`) REFERENCES `Proyecto_de_Investigacion` (`AIP`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Patentes`
--
ALTER TABLE `Patentes`
  ADD CONSTRAINT `fk_patentes_producto` FOREIGN KEY (`AIP`,`N_Secuencia`) REFERENCES `Productos` (`AIP`, `N_Secuencia`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Productos`
--
ALTER TABLE `Productos`
  ADD CONSTRAINT `fk_productos_proyecto` FOREIGN KEY (`AIP`) REFERENCES `Proyecto_de_Investigacion` (`AIP`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Prorroga`
--
ALTER TABLE `Prorroga`
  ADD CONSTRAINT `fk_prorroga_proyecto` FOREIGN KEY (`AIP`) REFERENCES `Proyecto_de_Investigacion` (`AIP`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Proyecto_de_Investigacion`
--
ALTER TABLE `Proyecto_de_Investigacion`
  ADD CONSTRAINT `fk_proyecto_finanza` FOREIGN KEY (`Cod_Finanza`) REFERENCES `Finanzas` (`Cod_Finanza`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_proyecto_programa` FOREIGN KEY (`Cod_Programa`) REFERENCES `Programa_Investigacion` (`Cod_Programa`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Filtros para la tabla `Publicacion_Congreso`
--
ALTER TABLE `Publicacion_Congreso`
  ADD CONSTRAINT `fk_pubcon_producto` FOREIGN KEY (`AIP`,`N_Secuencia`) REFERENCES `Productos` (`AIP`, `N_Secuencia`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Filtros para la tabla `Publicacion_Revista`
--
ALTER TABLE `Publicacion_Revista`
  ADD CONSTRAINT `fk_pubrev_clase` FOREIGN KEY (`Clase`) REFERENCES `Clasificacion_Revista` (`Clase`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_pubrev_producto` FOREIGN KEY (`AIP`,`N_Secuencia`) REFERENCES `Productos` (`AIP`, `N_Secuencia`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
