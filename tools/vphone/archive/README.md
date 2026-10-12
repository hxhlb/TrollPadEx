# Historical vphone experiments

`PhoneHostScaling.m` and `PhoneHostScalingControl.m` belong to the discarded
Phone-only proportional-hosting experiment. They are retained for reproducing
historical research, not for building or installing the current feature.

Neither file is referenced by the production Makefile or included in either
package. Current **Allow Smaller Windows** uses native app layout through
`TPWindowScaling.m`; it does not use these transforms or the temporary
`TPTrollPadExPhoneHostScaling` preference.

See [the archived investigation](../../../docs/research/IOS26-PROPORTIONAL-SCALING.md)
for its bounded results and VM-only reproduction steps.
