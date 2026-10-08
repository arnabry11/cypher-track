package org.traccar.client

import kotlin.time.Clock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// Emits one starting fix per enabled period. Unlike requestPosition(), callers
// can merge this into TrackerEngine's normal filtered, offline-buffered path.
@OptIn(ExperimentalCoroutinesApi::class)
internal fun initialFixes(
    state: StateFlow<State>,
    locationSource: LocationSource,
    nowMillis: () -> Long = { Clock.System.now().toEpochMilliseconds() },
): Flow<Position> = channelFlow {
    state.map { it.enabled }.distinctUntilChanged().collectLatest { enabled ->
        if (!enabled) return@collectLatest
        val requestedAt = nowMillis()
        val fix = locationSource.fetchFreshOnce(requestedAt) ?: return@collectLatest
        // fetchOnce can fall back to the OS location cache. A pre-trip fix must
        // never be represented as the trip's starting position.
        if (fix.time >= requestedAt) send(fix)
    }
}
