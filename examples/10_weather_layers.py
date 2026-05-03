# Weather layer demo — toggle wind particles on the map.
#
# Run this script with the map panel open (click the globe icon in
# the toolbar). The wind particle layer will animate over whatever
# tile basemap is currently active.

# Fly to Houston TX at a good zoom for wind visualisation.
map_fly_to(29.76, -95.37, zoom=7, animated=True)

# Enable the wind particle overlay.
map_set_weather_layer("wind", enabled=True)

print("Wind layer active. Particles are coloured blue→yellow by speed.")
print("Thicker streaks = faster wind.")
print()
print("To disable:  map_set_weather_layer('wind', enabled=False)")
print("Other layers (planned): temperature, rain, snow, lightning,")
print("                         storms, hail, clouds, drought")
