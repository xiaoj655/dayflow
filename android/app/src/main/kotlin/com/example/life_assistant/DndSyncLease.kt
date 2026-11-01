package com.example.life_assistant

/** Persistent ownership of the Xiaomi manual-DND flag. This class has no Android
 * dependency so interruption, restart and rollback behavior can be tested directly.
 */
internal class DndSyncLease(
    private val store: Store,
    private val read: () -> Int,
    private val dndWasOn: () -> Boolean,
    private val write: (Int) -> Unit,
    private val canWrite: () -> Boolean,
) {
    enum class State { IDLE, PREPARED, OWNED, PRESERVED, OVERRIDDEN }
    interface Store { var state: State }
    val pending: Boolean get() = store.state != State.IDLE

    @Synchronized fun prepare() {
        if (store.state != State.IDLE) {
            observe()
            return
        }
        check(canWrite()) { "手机勿扰联动尚未授权，请连接电脑完成一次授权" }
        store.state = if (read() == 0 && !dndWasOn()) State.PREPARED else State.PRESERVED
    }

    @Synchronized fun activate() {
        if (store.state != State.PREPARED) return
        // Another actor may have enabled DND while our own rule was being set up.
        if (read() != 0) {
            store.state = State.PRESERVED
            return
        }
        // Persist responsibility before a write that can partially succeed.
        store.state = State.OWNED
        write(1)
    }

    @Synchronized fun observe() {
        if (store.state == State.OWNED && read() != 1) store.state = State.OVERRIDDEN
    }

    @Synchronized fun release(): Boolean {
        if (store.state == State.OWNED && read() == 1) {
            // Retain the lease if permission is revoked or the write fails;
            // a later idle snapshot can retry rather than losing responsibility.
            if (!canWrite()) return false
            write(0)
        }
        store.state = State.IDLE
        return true
    }
}
