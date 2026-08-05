package it.letscode.tougedash.video

import it.letscode.tougedash.data.local.OverlayTemplateEntity
import kotlinx.serialization.Serializable

@Serializable
data class VideoOverlayTemplateDefinition(
    val style: OverlayStyle,
    val portraitX: Float = 0f,
    val portraitY: Float = -0.72f,
    val landscapeX: Float = 0f,
    val landscapeY: Float = -0.70f,
    val scale: Float = 0.92f
) {
    fun x(portrait: Boolean) = if (portrait) portraitX else landscapeX
    fun y(portrait: Boolean) = if (portrait) portraitY else landscapeY

    fun positioned(portrait: Boolean, x: Float, y: Float, scale: Float = this.scale) =
        if (portrait) copy(portraitX = x, portraitY = y, scale = scale)
        else copy(landscapeX = x, landscapeY = y, scale = scale)
}

data class VideoOverlayTemplate(
    val entity: OverlayTemplateEntity,
    val definition: VideoOverlayTemplateDefinition
)
