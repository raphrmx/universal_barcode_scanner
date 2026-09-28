package be.comapps.universal_barcode_scanner

import org.junit.Assert.assertEquals
import org.junit.Test

/** The same cases as the page's `accept`, which the other platforms mirror. */
class ReadGateTest {

    private fun run(delay: Long, vararg reads: Pair<String, Long>): List<Boolean> {
        val gate = ReadGate(delay)
        return reads.map { (value, now) -> gate.accept(value, now) }
    }

    @Test
    fun aCodeHeldInSightIsReportedOnce() {
        assertEquals(
            listOf(true, false, false, false),
            run(0, "A" to 0, "A" to 400, "A" to 800, "A" to 1200),
        )
    }

    @Test
    fun aCodeIsReportedAgainAfterASecondOutOfSight() {
        assertEquals(listOf(true, true), run(0, "A" to 0, "A" to 2500))
    }

    @Test
    fun twoCodesInSightAreEachReportedOnce() {
        assertEquals(
            listOf(true, true, false, false, false),
            run(0, "A" to 0, "B" to 50, "A" to 100, "B" to 150, "A" to 200),
        )
    }

    @Test
    fun aCodeTheDelayHeldBackGoesOutWhenTheDelayAllows() {
        assertEquals(
            listOf(true, false, false, true, false),
            run(2000, "A" to 0, "A" to 1500, "A" to 1600, "A" to 2100, "A" to 2200),
        )
    }

    @Test
    fun resetReportsTheCodeInSightAgain() {
        val gate = ReadGate(0)
        assertEquals(true, gate.accept("A", 0))
        gate.reset()
        assertEquals(true, gate.accept("A", 100))
    }
}
