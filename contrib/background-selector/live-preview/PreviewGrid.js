// 4x7 physical-pixel units preserve the 8x14 cell ratio without interpolation.
function metrics(width,height,cols,rows,dpr,globalX,globalY) {
  dpr=Math.max(1,dpr||1)
  var unit=Math.max(1,Math.floor(Math.min(width*dpr*0.92/(cols*4),height*dpr*0.92/(rows*7))))
  var cw=4*unit,ch=7*unit
  var gx=globalX*dpr,gy=globalY*dpr
  return {cw:cw/dpr,ch:ch/dpr,
    x:(Math.round(gx+(width*dpr-cw*cols)/2)-gx)/dpr,
    y:(Math.round(gy+(height*dpr-ch*rows)/2)-gy)/dpr,
    font:Math.max(2,Math.floor(Math.min(ch*0.82,cw*1.55)))/dpr,
    pixelWidth:cw,pixelHeight:ch}
}
