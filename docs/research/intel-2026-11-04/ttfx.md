# Comparación física en Intel — 2026-11-04

Intel Core i5-5257U / Iris 6100, 2560×1600, escala 2. CPU en porcentaje de un núcleo. Dos muestras por condición, orden de ida y vuelta, 6 s de calentamiento y 15–20 s de medida; enfriamiento a ≤68 °C antes de cada muestra.

La referencia instalada tiene SHA256 `6f9b0f7e…`; el combinado probado `9cb29d9c…`. El combinado incluye las optimizaciones anteriores de escenas y las cachés/filas parciales de TTFx. La instalación no se reemplazó.

## TTFx: instalado frente al combinado

| Efecto | Instalado CPU % | Combinado CPU % | Reducción CPU |
|---|---:|---:|---:|
| matrix | 5.06 | 4.86 | 3.9 % |
| beams | 4.75 | 3.68 | 22.4 % |
| rings | 3.38 | 3.07 | 9.3 % |
| decrypt | 2.72 | 2.55 | 6.4 % |
| thunderstorm | 3.13 | 2.97 | 4.9 % |

Beams tiene la señal más clara en esta tanda (3,68 % en ambas muestras nuevas frente a 4,65–4,85 % instalado). Rings y Decrypt mejoran modestamente. Matrix y Thunderstorm cambian poco. Son muestras cortas: no se debe extrapolar una reducción pequeña a todas las fases del efecto.

## Terminal frente a GPU con lienzo y límite igualados

Mismo branding y lienzo de 237×61; límite solicitado de 20 fps. Terminal: Foot 1.28 + TTFx CLI 0.5.0 y fuente de 6,5 puntos para alojar el lienzo. GPU: resolución 2. No hay equivalencia de píxeles entre las fuentes y paletas.

| Efecto | Foot+TTFx CPU % | Combinado CPU % | Foot GPU fuera RC6 % | Combinado GPU fuera RC6 % |
|---|---:|---:|---:|---:|
| matrix | 123.70 | 4.86 | 12.60 | 23.83 |
| beams | 126.10 | 3.68 | 12.51 | 20.90 |
| rings | 113.15 | 3.07 | 12.32 | 20.06 |
| decrypt | 111.40 | 2.55 | 12.28 | 13.94 |
| thunderstorm | 111.97 | 2.97 | 12.54 | 19.48 |

La CPU cae fuertemente, pero la ocupación GPU global aumenta en esta comparación. RC6 no mide watts ni batería. El renderer informa aproximadamente 20 fps (Decrypt ~16); no se midieron cuadros presentados de la terminal: 20 fps es su límite solicitado. Por ello este bloque no acredita una eficiencia por cuadro ni una igualdad visual exacta.

## Configuración normal de la terminal

Foot con la configuración de screensaver de Omarchy, fuente de 18 puntos, canvas automático observado de 88×25 y límite solicitado de 120 fps. Se fija el efecto para medirlo, omitiendo el bucle aleatorio y el sondeo de foco del launcher. Nuestro uso configurado es 237×61 a 20 fps: es una comparación de configuraciones cotidianas, con densidad y cadencia distintas.

| Efecto | Foot+TTFx CPU % | Combinado CPU % | Foot GPU fuera RC6 % | Combinado GPU fuera RC6 % | Máx. terminal °C |
|---|---:|---:|---:|---:|---:|
| matrix | 134.86 | 4.86 | 45.93 | 23.83 | 84 |
| rings | 135.47 | 3.07 | 47.58 | 20.06 | 82 |
| thunderstorm | 133.65 | 2.97 | 47.26 | 19.48 | 82 |

La prueba adicional de 120 fps con el lienzo denso 237×61 se interrumpió por superar 90 °C (Matrix y Beams). Esos tres registros están separados y no se usan para calcular la comparación a 20 fps.

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
