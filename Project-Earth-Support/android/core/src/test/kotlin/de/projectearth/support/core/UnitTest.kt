package de.projectearth.support.core

import kotlin.test.Test
import kotlin.test.assertEquals

/** Laeuft bei "gradle :core:test": Einladungscode, u-law, IPv4/UDP-Huelle und der zuverlaessige Strom mit Paketverlust. */
class UnitTest {
    @Test
    fun kernOhneNetz() {
        assertEquals(0, SelfTest.runUnit(), "Kern-Pruefungen ohne Netz")
    }
}
