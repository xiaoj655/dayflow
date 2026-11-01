package com.example.life_assistant

import org.junit.Assert.*
import org.junit.Test

class DndSyncLeaseTest {
    private class Saved : DndSyncLease.Store { override var state = DndSyncLease.State.IDLE }
    private class Device {
        var manual = 0
        var dndOn = false
        var permission = true
        var failWrite = false
        val writes = mutableListOf<Int>()
        fun lease(saved: Saved) = DndSyncLease(saved, { manual }, { dndOn }, {
            manual = it
            writes.add(it)
            if (failWrite) error("write failed after changing state")
        }, { permission })
    }

    @Test fun startPauseResumeAndEndOnlyRestoreOwnedState() {
        val saved = Saved(); val device = Device(); val lease = device.lease(saved)
        lease.prepare(); lease.activate()
        assertEquals(listOf(1), device.writes)
        lease.prepare(); lease.activate() // Boot/repeated acquire doesn't replace the baseline.
        assertTrue(lease.release())
        assertEquals(listOf(1, 0), device.writes)
        lease.prepare(); lease.activate(); lease.release()
        assertEquals(listOf(1, 0, 1, 0), device.writes)
    }
    @Test fun preexistingManualOrAutomaticDndIsPreserved() {
        for (manual in listOf(0, 1)) {
            val device = Device(); device.manual = manual; device.dndOn = true
            val lease = device.lease(Saved())
            lease.prepare(); lease.activate(); lease.release()
            assertTrue(device.writes.isEmpty())
            assertEquals(manual, device.manual)
        }
    }
    @Test fun anotherActorEnablingBetweenPrepareAndActivateIsNotTakenOver() {
        val device = Device(); val lease = device.lease(Saved())
        lease.prepare(); device.manual = 1; lease.activate(); lease.release()
        assertTrue(device.writes.isEmpty()); assertEquals(1, device.manual)
    }
    @Test fun userTurningOffThenOnTakesOwnershipUntilEnd() {
        val device = Device(); val lease = device.lease(Saved())
        lease.prepare(); lease.activate()
        device.manual = 0; lease.observe()
        device.manual = 1; lease.observe()
        lease.prepare(); lease.activate(); lease.release()
        assertEquals(listOf(1), device.writes); assertEquals(1, device.manual)
    }
    @Test fun restartKeepsTheOriginalLeaseForBackgroundCompletion() {
        val saved = Saved(); val device = Device()
        device.lease(saved).also { it.prepare(); it.activate() }
        device.lease(saved).release()
        assertEquals(listOf(1, 0), device.writes)
    }
    @Test fun missingPermissionCannotAcceptANewLease() {
        val device = Device(); device.permission = false
        val saved = Saved()
        assertThrows(IllegalStateException::class.java) { device.lease(saved).prepare() }
        assertEquals(DndSyncLease.State.IDLE, saved.state)
        assertTrue(device.writes.isEmpty())
    }
    @Test fun revokedPermissionKeepsRestorationForRetry() {
        val device = Device(); val saved = Saved(); val lease = device.lease(saved)
        lease.prepare(); lease.activate(); device.permission = false
        assertFalse(lease.release()); assertTrue(lease.pending)
        device.permission = true
        assertTrue(device.lease(saved).release()); assertEquals(0, device.manual)
    }
    @Test fun partiallyFailedStartCanRollBack() {
        val device = Device(); val saved = Saved(); val lease = device.lease(saved)
        lease.prepare(); device.failWrite = true
        assertThrows(IllegalStateException::class.java) { lease.activate() }
        assertEquals(DndSyncLease.State.OWNED, saved.state)
        device.failWrite = false; lease.release()
        assertEquals(listOf(1, 0), device.writes)
    }
}
