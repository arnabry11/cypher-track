package org.traccar.client

import kotlinx.coroutines.flow.StateFlow

interface TrackingStateStore {
    val state: StateFlow<State>
    suspend fun update(transform: (State) -> State)
}
