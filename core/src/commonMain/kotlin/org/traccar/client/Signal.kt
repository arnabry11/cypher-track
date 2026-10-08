package org.traccar.client

sealed interface Signal {
    object StationaryEnter : Signal
    object StationaryExit : Signal
    object HeartbeatTick : Signal
}
