use std::collections::BTreeMap;

use anyhow::Result;
use image::{DynamicImage, GenericImageView, imageops::FilterType};
use material_colors::color::Argb;
use material_colors::hct::Hct;

pub(crate) fn extract_source_color(image: &DynamicImage) -> Result<Argb> {
    let resized = image.resize(256, 256, FilterType::Triangle);
    let rgba = resized.to_rgba8();
    let mut bins = BTreeMap::<u16, Bin>::new();

    for pixel in rgba.pixels() {
        let [r, g, b, a] = pixel.0;
        if a < 200 {
            continue;
        }

        let rgb = Argb::new(255, r, g, b);
        let hct = Hct::new(rgb);
        let chroma = hct.get_chroma();
        let tone = hct.get_tone();

        if chroma < 8.0 || !(8.0..=96.0).contains(&tone) {
            continue;
        }

        let key = quantize_key(hct.get_hue(), chroma, tone);
        bins.entry(key)
            .and_modify(|bin| bin.add(rgb, chroma, tone))
            .or_insert_with(|| Bin::new(rgb, chroma, tone));
    }

    let best = bins
        .into_values()
        .max_by(|left, right| left.score().total_cmp(&right.score()))
        .map(Bin::color)
        .unwrap_or_else(|| fallback_source_color(image));

    Ok(best)
}

fn fallback_source_color(image: &DynamicImage) -> Argb {
    let pixel = image.get_pixel(image.width() / 2, image.height() / 2).0;
    Argb::new(255, pixel[0], pixel[1], pixel[2])
}

fn quantize_key(hue: f64, chroma: f64, tone: f64) -> u16 {
    let hue_bucket = (hue / 12.0).round() as u16;
    let chroma_bucket = (chroma / 8.0).round() as u16;
    let tone_bucket = (tone / 8.0).round() as u16;

    (hue_bucket << 8) | (chroma_bucket << 4) | tone_bucket
}

#[derive(Clone, Copy)]
struct Bin {
    red: f64,
    green: f64,
    blue: f64,
    count: f64,
    chroma_sum: f64,
    tone_sum: f64,
}

impl Bin {
    fn new(color: Argb, chroma: f64, tone: f64) -> Self {
        Self {
            red: f64::from(color.red),
            green: f64::from(color.green),
            blue: f64::from(color.blue),
            count: 1.0,
            chroma_sum: chroma,
            tone_sum: tone,
        }
    }

    fn add(&mut self, color: Argb, chroma: f64, tone: f64) {
        self.red += f64::from(color.red);
        self.green += f64::from(color.green);
        self.blue += f64::from(color.blue);
        self.count += 1.0;
        self.chroma_sum += chroma;
        self.tone_sum += tone;
    }

    fn color(self) -> Argb {
        Argb::new(
            255,
            (self.red / self.count).round() as u8,
            (self.green / self.count).round() as u8,
            (self.blue / self.count).round() as u8,
        )
    }

    fn score(self) -> f64 {
        let chroma = self.chroma_sum / self.count;
        let tone = self.tone_sum / self.count;
        let tone_balance = 1.0 - ((tone - 55.0).abs() / 55.0).min(1.0);

        self.count.powf(1.15) * (1.0 + chroma / 48.0) * (0.5 + tone_balance)
    }
}
