package org.traccar.client

interface Uploader {
    suspend fun upload(position: Position): Boolean
}
