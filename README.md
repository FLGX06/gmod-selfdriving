# Garry's Mod Wiremod Self-Driving
This code allows Garry's Mod vehicles primarily from simfphys to drive themselves using Expressions 2 from Wiremod. Rangers are used as inputs and also a speedometer. Should work perfectly on a road with high walls. Also has adaptive cruise control if there's a vehicle or any other object in front and partially automatic emergency braking (AEB).

## Rangers
* Front - facing forward
* Left - face about 50-90° left
* Right - face about 50-90° right

## Inputs
**Make sure output distance, output velocity, output entity+entid is enabled in the ranger spawn menu**

* Front - front ranger distance
* Left - left ranger distance
* Right - right ranger distance
* Driver - driver of the vehicle (disabled when there's a driver as in simfphys it can't control steering at least for me)
* Speed - speedometer garry's mod speed (Out output)
* VX - front ranger VX (velocity)
* VY - front ranger VY (velocity)
* VZ - front ranger VZ (velocity)
* FrontID - front ranger EntityID

## Outputs
* Engine
* Throttle
* Steer
* Brake
* Handbrake
* Beep - sound warning
* RGB - rgb of the light 