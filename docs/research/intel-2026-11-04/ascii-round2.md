# Intel: segunda ronda de optimización ASCII y controles TTFx

Fecha: 2026-11-04. Intel Core i5-5257U, Iris6100, 2560×1600 escala2. Se compara el renderer ya optimizado de la primera ronda con el nuevo candidato; no con la terminal stock.

## Resultado

| Escena/control | CPU referencia % | CPU nueva % | Cambio CPU | Paquete referencia W | Paquete nuevo W |
|---|---:|---:|---:|---:|---:|
| neon-city | 4.187 | 3.965 | -5.3 % | 5.470 | 5.467 |
| circuit-run | 3.815 | 3.531 | -7.4 % | 5.433 | 5.365 |
| ttfx:beams | 1.260 | 1.285 | +2.0 % | 4.815 | 4.742 |
| ttfx:matrix | 1.938 | 1.951 | +0.6 % | 5.026 | 5.027 |
| sand-clock-galaxy | 1.817 | 1.837 | +1.1 % | 5.126 | 5.113 |

CPU es porcentaje de un núcleo; cambio negativo es menos CPU. NeonCity y CircuitRun reducen trabajo con la misma densidad, efectos y cadencia de20fps. Los controles TTFx y Galaxy deben leerse con sus rangos de repetición, no como mejoras generales.

La energía del paquete no muestra una reducción general concluyente en esta tanda: las diferencias son pequeñas y hay variación entre muestras. RAPL es energía del paquete del procesador (incluye dominios compartidos), no potencia del equipo completo ni autonomía.

## Método y controles

- Orden A/B/B/A por escenario, dos muestras por variante.10s de calentamiento;40s de medida en City,Circuit,Beams,Matrix;25s en Galaxy.20 muestras finales.
- Mismos argv/env capturados para cada fuente, sin cambiar resolución, fps ni música. City/Circuit corren a304×72; los TTFx a237×61. No se ejecutan pruebas/compiladores simultáneos en Intel.
- Governor `performance` temporal para fijar aproximadamente3.1GHz; se guardan los valores originales y se restauran al terminar. Un watchdog limita el ensayo a30min. Esta comparación controlada no se mezcla con los números previos bajo `schedutil`.
- El primer ensayo exploratorio bajo schedutil varió demasiado de frecuencia y quedó separado. El candidato intermedio final2 mejoró el camino denso pero mostró un pequeño sobrecoste de fill en los controles; se especializaron los bucles disperso/denso antes de esta comparación final.
- CPU del árbol completo y de cada hilo, Hyprland aparte, temperatura y frecuencia por segundo. RC6 es una estimación global de ocupación GPU, no watts.
- Energía RAPL leída con privilegios de diagnóstico al inicio/final; potencia media = delta de microjoules / tiempo, contemplando vuelta del contador. Se informa package-0; los dominios core/uncore/dram se conservan en los crudos.
- Los cuadros GPU se observan mediante las estadísticas del renderer, no se infieren solo del límite. Los replays de igualdad conservan celdas y fingerprint; los11 gatesGPU comparan nuestros perfiles, no nuestra app contraFoot.

## Trabajo eliminado

1. Frames densos (≥25% de la cuadrícula) detectan cambios por filas/tiles contiguos; los dispersos conservan las listas de celdas.
2. El fill elige una vez por cuadro el bucle const-generic denso o disperso. Así se elimina la comprobación dense/memo por celda del camino disperso.
3. Las celdas densas consecutivas con el mismo carácter/estilo reutilizan su slot de glifo. La caché es local al fill/reintento y no sobrevive resets del atlas.
4. Circuit reutiliza alturas de vértices del terreno mientras permanece en el mismo strip de mundo; no cambia su geometría ni el cálculo de interpolación.
5. Las líneas conservan primero el fast path original dentro del viewport; luego pueden descartar segmentos completamente fuera de un mismo lado. Los no finitos/overflow conservan la aritmética general.
6. El fingerprint de escenas Raster se calcula al entregar celdas, sin volver a recorrer el Vec. Previews mantienen draw sin hash y Showcase conserva el hash anterior.

## Etapas observadas en Intel

| Escena | Variante | Fill µs/cuadro | Damage µs/cuadro | CPU Wayland µs/cuadro | FPS observados |
|---|---|---:|---:|---:|---:|
| neon-city | base | 91.6 | 154.1 | 624.9 | 20.00 |
| neon-city | final3 | 91.1 | 37.0 | 505.1 | 20.00 |
| circuit-run | base | 84.7 | 131.2 | 592.8 | 20.00 |
| circuit-run | final3 | 78.5 | 28.9 | 474.4 | 20.00 |
| ttfx:beams | base | 15.5 | 30.9 | 449.0 | 19.60 |
| ttfx:beams | final3 | 19.3 | 31.3 | 450.1 | 19.56 |
| ttfx:matrix | base | 31.8 | 49.9 | 474.8 | 19.80 |
| ttfx:matrix | final3 | 40.9 | 50.6 | 477.1 | 19.80 |
| sand-clock-galaxy | base | 23.4 | 54.8 | 445.5 | 20.00 |
| sand-clock-galaxy | final3 | 32.9 | 55.7 | 461.9 | 20.00 |

Los tiempos de etapa y el coste por cuadro dependen de la frecuencia y de los cuadros observados; no se traducen directamente al porcentaje total del programa.

## Rangos de repetición y energía

| Escena/control | Variante | CPU % mínimo–máximo | Paquete W mínimo–máximo | GPU fueraRC6 % mediana | Máx °C | Frecuencia MHz mediana |
|---|---|---:|---:|---:|---:|---:|
| neon-city | base | 4.175–4.199 | 5.457–5.483 | 24.56 | 70 | 3093 |
| neon-city | final3 | 3.952–3.978 | 5.439–5.495 | 24.55 | 70 | 3100 |
| circuit-run | base | 3.803–3.828 | 5.390–5.477 | 24.21 | 72 | 3100 |
| circuit-run | final3 | 3.507–3.555 | 5.362–5.367 | 24.38 | 67 | 3096 |
| ttfx:beams | base | 1.235–1.285 | 4.777–4.853 | 19.22 | 68 | 3091 |
| ttfx:beams | final3 | 1.260–1.309 | 4.709–4.775 | 19.31 | 64 | 3097 |
| ttfx:matrix | base | 1.926–1.950 | 5.021–5.031 | 23.57 | 65 | 3100 |
| ttfx:matrix | final3 | 1.951–1.951 | 5.007–5.046 | 23.48 | 65 | 3100 |
| sand-clock-galaxy | base | 1.817–1.818 | 5.116–5.135 | 21.58 | 65 | 3100 |
| sand-clock-galaxy | final3 | 1.818–1.857 | 5.108–5.117 | 21.39 | 69 | 3093 |

## Validación y preparación

- Renderer integrado:234 pruebas principales, biblioteca/puente/grupos aislados y11 pruebasGPU pasan en M2; la misma suite y los11 gatesGPU también pasaron en Intel con el candidato final.
- Selector: suite215 aserciones, instalador52, Python14; harness reproducible32000celdas×3rutas del parser y18 pares CPU/snapshot/save. El harness del selector acredita parser/CPU, no equivalencia de su shader GPU.
- Se descartaron el hoisting explícito por fila (sin ganancia repetible), memo de glifos en escenas dispersas (regresión) y el candidato intermedio con checks dense/memo por celda.
- Bundles de ensayo0.4.1-round-test por arquitectura: deben contener `libambientcells.so`, manifest/version/entryPoint coherentes, renderer esperado y checksum correcto. Son artefactos de ensayo; no se etiquetó/publicó un release ni se reemplazaron instalaciones.

## Evidencia

- [Muestras finales resumidas](samples-round2.jsonl).
- [Muestras CSV](samples-round2.csv).
- [Procedencia](provenance-round2.json).
- [Comprobación bundleARM](bundle-arm-round2.json) y [bundle x86](bundle-x86-round2.json).
- Crudos completos, scripts, parches y artefactos: `/var/tmp/ambient-ascii-round-20261104/` en M2; `/tmp/ascii-round-20261104/` en Intel.


## Entrega y estado final

Renderer: commits locales `95df5e1` (tanda previa consolidada) y `bfeaa91` (esta ronda). Selector: `f9f1386` (GPU/stream/instalador) y `d590225` (harness reproducible). Los bundles son de ensayo0.4.1-round-test, con ELF y hashes verificados por arquitectura; versiones de producción y tags sin cambios. Intel volvió a `none`, sin renderer ni captura de prueba y con los cuatro governors originales `schedutil`. Su binario instalado conserva SHA256 `6f9b0f7e…`.

El binario instalado en M2 conserva SHA256 `cddfa631…`. Su estado leído al cierre es `none`; no se forzó un cambio de fondo. Los bundles nuevos permanecen como artefactos de ensayo.
