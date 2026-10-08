package org.traccar.client

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

class TrackerEngineTest {

    @Test
    fun startAndHeartbeatFixesEnterOfflineQueueOnlyDuringTracking() = runBlocking {
        val state = MemoryStateStore(State())
        val queue = MemoryQueue()
        val network = object : NetworkMonitor {
            override val isOnline = MutableStateFlow(false)
        }
        var requests = 0
        val source = object : LocationSource {
            override val positions = emptyFlow<Position>()
            override suspend fun fetchOnce(): Position? = error("must fetch a fresh fix")
            override suspend fun fetchFreshOnce(sinceMillis: Long): Position {
                requests++
                return Position(latitude = 1.0, longitude = 2.0, time = sinceMillis)
            }
        }
        val scope = ComponentCoroutineScope()
        try {
            val engine = TrackerEngine(
                stateStore = state,
                queue = queue,
                network = network,
                locationSource = source,
                signalSources = emptyList(),
                processors = listOf(PositionProcessor { it }),
                uploader = object : Uploader {
                    override suspend fun upload(position: Position): Boolean =
                        error("must not upload while offline")
                },
                buffer = true,
                scope = scope,
            )

            assertEquals(0, requests)
            state.update(State::forNewTrackingPeriod)
            withTimeout(2_000L) { queue.enqueued.receive() }
            assertEquals(1, requests)

            engine.handle(Signal.HeartbeatTick)
            val heartbeat = withTimeout(2_000L) { queue.enqueued.receive() }
            assertTrue(heartbeat.forceReport)
            assertEquals(2, queue.items.size)

            state.update { it.copy(enabled = false) }
            val requestsBeforeStopTick = requests
            engine.handle(Signal.HeartbeatTick)
            assertEquals(requestsBeforeStopTick, requests)
            assertEquals(2, queue.items.size)
        } finally {
            scope.cancel()
        }
    }

    private class MemoryStateStore(initial: State) : TrackingStateStore {
        private val mutableState = MutableStateFlow(initial)
        override val state: StateFlow<State> = mutableState

        override suspend fun update(transform: (State) -> State) {
            mutableState.value = transform(mutableState.value)
        }
    }

    private class MemoryQueue : PositionQueue {
        val items = mutableListOf<Position>()
        val enqueued = Channel<Position>(Channel.UNLIMITED)

        override suspend fun enqueue(position: Position) {
            items.add(position)
            enqueued.send(position)
        }

        override suspend fun peek(): Position? = items.firstOrNull()

        override suspend fun removeFirst() {
            items.removeAt(0)
        }
    }
}
