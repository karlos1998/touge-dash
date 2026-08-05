package it.letscode.tougedash.performance

import it.letscode.tougedash.data.local.AccelerationAttemptEntity
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class AccelerationType(val startKph: Double, val endKph: Double) {
    @SerialName("ZERO_TO_100") ZERO_TO_100(0.0, 100.0),
    @SerialName("HUNDRED_TO_200") HUNDRED_TO_200(100.0, 200.0),
    @SerialName("TWO_HUNDRED_TO_250") TWO_HUNDRED_TO_250(200.0, 250.0);

    val label: String get() = when (this) {
        ZERO_TO_100 -> "0–100"
        HUNDRED_TO_200 -> "100–200"
        TWO_HUNDRED_TO_250 -> "200–250"
    }
}

@Serializable
data class ActiveAcceleration(
    val type: AccelerationType,
    val startedAt: Long,
    val elapsedMillis: Long,
    val currentSpeedKph: Double,
    val progress: Double
)

data class AccelerationRuntimeState(
    val active: ActiveAcceleration? = null,
    val recentResults: List<AccelerationAttemptEntity> = emptyList()
)

