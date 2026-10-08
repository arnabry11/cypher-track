package org.traccar.client

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json

@OptIn(ExperimentalCoroutinesApi::class)
class InitialFixesTest {

    @Test
    fun newTrackingPeriodClearsPreviousTripThreshold() {
        val previous = Position(latitude = 1.0, longitude = 2.0, time = 1L)
        val state = State(enabled = false, paused = true, lastAcceptedLocation = previous)

        val started = state.forNewTrackingPeriod()

        assertTrue(started.enabled)
        assertFalse(started.paused)
        assertNull(started.lastAcceptedLocation)
    }

    @Test
    fun obtainsOneFreshFixOnEachStart() = runTest {
        val state = MutableStateFlow(State())
        val fixes = listOf(
            Position(latitude = 1.0, longitude = 2.0, time = 101_001L),
            Position(latitude = 3.0, longitude = 4.0, time = 101_002L),
        )
        var calls = 0
        val source = object : LocationSource {
            override val positions = emptyFlow<Position>()
            override suspend fun fetchOnce(): Position? = error("must request a fresh fix")
            override suspend fun fetchFreshOnce(sinceMillis: Long): Position {
                assertEquals(101_000L, sinceMillis)
                return fixes[calls++]
            }
        }
        val received = mutableListOf<Position>()
        backgroundScope.launch {
            initialFixes(state, source, nowMillis = { 101_000L }).collect { received.add(it) }
        }
        runCurrent()

        state.value = State(enabled = true)
        runCurrent()
        state.value = State(enabled = false)
        runCurrent()
        state.value = State(enabled = true)
        runCurrent()

        assertEquals(fixes, received)
        assertEquals(2, calls)
    }

    @Test
    fun stopCancelsPendingFixAndNoPositionIsRequestedWhileStopped() = runTest {
        val state = MutableStateFlow(State())
        val pending = CompletableDeferred<Position?>()
        var calls = 0
        val source = source {
            calls++
            pending.await()
        }
        val received = mutableListOf<Position>()
        backgroundScope.launch {
            initialFixes(state, source, nowMillis = { 101_000L }).collect { received.add(it) }
        }
        runCurrent()
        assertEquals(0, calls)

        state.value = State(enabled = true)
        runCurrent()
        assertEquals(1, calls)
        state.value = State(enabled = false)
        runCurrent()
        pending.complete(Position(latitude = 1.0, longitude = 2.0, time = 101_001L))
        runCurrent()

        assertEquals(emptyList(), received)
        assertEquals(1, calls)
    }

    @Test
    fun rejectsCachedFixFromBeforeStart() = runTest {
        val state = MutableStateFlow(State())
        val received = mutableListOf<Position>()
        backgroundScope.launch {
            initialFixes(
                state,
                source { Position(latitude = 1.0, longitude = 2.0, time = 100_999L) },
                nowMillis = { 101_000L },
            ).collect { received.add(it) }
        }
        runCurrent()

        state.value = State(enabled = true)
        runCurrent()

        assertEquals(emptyList(), received)
    }

    @Test
    fun heartbeatForceFlagIsNotStoredOrSentAsPositionData() {
        val position = Position(latitude = 1.0, longitude = 2.0, time = 101_000L, forceReport = true)
        val encoded = Json.encodeToString(position)

        assertFalse(encoded.contains("forceReport"))
        assertFalse(Json.decodeFromString<Position>(encoded).forceReport)
    }

    private fun source(fetch: suspend () -> Position?): LocationSource = object : LocationSource {
        override val positions = emptyFlow<Position>()
        override suspend fun fetchOnce(): Position? = fetch()
    }
}
