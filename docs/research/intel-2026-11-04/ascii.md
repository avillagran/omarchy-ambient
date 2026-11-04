# Comparación física en Intel — 2026-11-04

Intel Core i5-5257U / Iris 6100, 2560×1600, escala 2. CPU en porcentaje de un núcleo. Dos muestras por condición, orden de ida y vuelta, 6 s de calentamiento y 15–20 s de medida; enfriamiento a ≤68 °C antes de cada muestra.

La referencia instalada tiene SHA256 `6f9b0f7e…`; el combinado probado `9cb29d9c…`. El combinado incluye las optimizaciones anteriores de escenas y las cachés/filas parciales de TTFx. La instalación no se reemplazó.

## Escenas ASCII densas: instalado frente al combinado

Mismos argumentos capturados de cada fuente, misma salida y límite de 20 fps. Incluye renderer, productor y proceso de captura de audio `parec`.

| Escena | Instalado CPU % (rango) | Combinado CPU % (rango) | Reducción mediana | Lectura |
|---|---:|---:|---:|---|
| neon-city | 8.58 (7.59–9.58) | 7.45 (6.84–8.06) | 13.2 % | Mejora aparente; rangos solapados |
| aquarium | 4.29 (4.24–4.35) | 4.23 (4.17–4.28) | 1.5 % | Prácticamente igual |
| circuit-run | 8.33 (7.92–8.75) | 7.70 (6.13–9.28) | 7.6 % | Variación amplia; ganancia no confirmada |

Esta tanda no demuestra una mejora general contundente en escenas ASCII densas. La ocupación GPU permanece cerca de 24 % global y los cuadros del renderer cerca de 20 fps. El resultado de los relojes de arena no debe extrapolarse a estas escenas.

Siguiente foco técnico: coste del productor y construcción/entrega de las listas de celdas en Neon City y Circuit Run. Se necesitan repeticiones más largas que cubran sus fases antes de promover una nueva optimización de esas escenas.

## Validación y evidencia

El binario combinado pasó la suite release sin características por defecto y las 11 pruebas de equivalencia de píxeles en la GPU Iris 6100. La equivalencia corresponde a nuestros perfiles de render, no a Foot frente a nuestra aplicación.

- [Informe completo y método](details.md).
- [Muestras individuales](samples.jsonl).
- [Muestras con fuente normal](stock-samples.jsonl).
- [Hashes y fuentes](provenance.json).
- Evidencia íntegra y scripts reproducibles: `/var/tmp/ttfx-intel-comparison-20261104/`.

CPU incluye todos los descendientes, incluso los que abren otra sesión de procesos; Hyprland se informa aparte en el detalle. GPU fuera de RC6 es global, sin descuento de reposo. RSS es suma de residentes, no PSS ni memoria GPU. No se leyó RAPL (permisos), por lo que no se afirma ahorro de watts o autonomía.


## Estado final verificado

Intel quedó en `none`, sin renderer, TTFx, Foot ni captura de audio de las pruebas. El hash instalado sigue siendo `6f9b0f7e…`. Tras enfriar, el sensor marcó 63 °C; Hyprland quedó sin CPU detectable en una ventana de 15 s. RC6 indica GPU aproximadamente en reposo (estimación cruda −0,65 %, desfase entre contadores; no ocupación negativa física). M2 conserva `sand-clock-dunes`.
