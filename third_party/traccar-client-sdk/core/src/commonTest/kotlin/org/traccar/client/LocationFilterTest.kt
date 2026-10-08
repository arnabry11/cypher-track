package org.traccar.client

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.runTest

class LocationFilterTest {

    @Test
    fun firstFixAfterNewTripIgnoresLastTripPosition() = runTest {
        val old = Position(latitude = 1.0, longitude = 2.0, time = 1_000L)
        val store = MemoryStateStore(State(lastAcceptedLocation = old))
        val filter = LocationFilter(config(), store)
        val nearby = Position(latitude = 1.0, longitude = 2.0, time = 2_000L)

        assertNull(filter.process(nearby))
        store.update(State::forNewTrackingPeriod)
        assertEquals(nearby, filter.process(nearby))
    }

    @Test
    fun heartbeatLocationBypassesSeventyFiveMetreFilter() = runTest {
        val previous = Position(latitude = 1.0, longitude = 2.0, time = 1_000L)
        val store = MemoryStateStore(State(enabled = true, lastAcceptedLocation = previous))
        val filter = LocationFilter(config(), store)
        val nearby = Position(latitude = 1.0, longitude = 2.0, time = 2_000L)

        assertNull(filter.process(nearby))
        assertEquals(nearby, filter.process(nearby.copy(forceReport = true)))
        assertEquals(nearby, store.state.value.lastAcceptedLocation)
    }

    private fun config() = Config(
        serverUrl = "https://example.org/",
        deviceId = "test",
        location = LocationConfig(distanceMeters = 75, heartbeatIntervalSeconds = 300),
    )

    private class MemoryStateStore(initial: State) : TrackingStateStore {
        private val mutableState = MutableStateFlow(initial)
        override val state: StateFlow<State> = mutableState

        override suspend fun update(transform: (State) -> State) {
            mutableState.value = transform(mutableState.value)
        }
    }
}
