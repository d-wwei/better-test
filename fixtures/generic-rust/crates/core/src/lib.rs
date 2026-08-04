pub fn answer() -> u32 {
    #[cfg(feature = "alternate-answer")]
    return 43;
    #[cfg(not(feature = "alternate-answer"))]
    42
}

#[cfg(test)]
mod tests {
    #[test]
    fn answers() {
        assert_eq!(super::answer(), 42);
    }
}
