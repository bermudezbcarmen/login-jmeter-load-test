# login-jmeter-load-test

## Ejecucion en Windows

Configurar `JMETER_HOME` y `JAVA_HOME` si las instalaciones estan en otra ruta.
El script usa por defecto `C:\tools\apache-jmeter-5.6.3` y, si esta disponible,
el JDK 18 instalado en esta maquina.

```bat
scripts\run-smoke-test.bat
scripts\run-load-test.bat
```

La prueba corta envia cinco logins, uno por cada usuario. La prueba de carga usa
el escenario de la tabla. Ambas generan un JTL, un log, un resumen JSON en
`results/` y un dashboard HTML en `reports/`, con nombres distintos para cada
ejecucion. No se guardan cuerpos de peticion ni tokens en los resultados.

Tambien se puede abrir `test-plan/login-load-test.jmx` en JMeter y editar
`User Defined Variables`. Para ejecutar la carga se recomienda el modo sin GUI.
